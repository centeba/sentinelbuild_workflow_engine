// Multi-model chat — embeddable widget.
//
// A self-contained chat panel any SentinelBuild host can drop in. It takes its
// two authenticated Dio clients by constructor (user-master + doc-vault), an
// optional `translate` for host i18n (English fallbacks otherwise), and an
// optional `pickFile` so the host owns platform file-picking (the chassis wires
// a web picker; other hosts can use file_picker). No Scaffold — embed it in a
// page, panel, or drawer. The conversation auto-binds to the company's generic
// "Chat Assistant"; the per-turn model dropdown overrides the model.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'chat_api.dart';

class EmbeddedChat extends StatefulWidget {
  const EmbeddedChat({
    super.key,
    required this.userMasterDio,
    required this.docVaultDio,
    this.translate,
    this.pickFile,
  });

  final Dio userMasterDio;
  final Dio docVaultDio;

  /// Host i18n lookup; when null, built-in English strings are used.
  final String Function(String key)? translate;

  /// Host-supplied file picker for document attachments. When null, the attach
  /// affordance is hidden (keeps this package platform-agnostic).
  final Future<PickedFile?> Function()? pickFile;

  @override
  State<EmbeddedChat> createState() => _EmbeddedChatState();
}

const _en = {
  'chat.new_chat': 'New chat',
  'chat.no_threads': 'No conversations yet',
  'chat.delete': 'Delete',
  'chat.empty_title': 'Start a conversation',
  'chat.empty_hint': 'Ask anything. Pick a model below.',
  'chat.answered_by': 'Answered by',
  'chat.composer_hint': 'Message the assistant…',
  'chat.models_unavailable': 'Models unavailable',
  'chat.no_key': 'no key',
  'chat.attach': 'Attach a document',
  'chat.attaching': 'Uploading…',
};

class _EmbeddedChatState extends State<EmbeddedChat> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  late final ChatApi _api = ChatApi(
    userMasterDio: widget.userMasterDio,
    docVaultDio: widget.docVaultDio,
  );

  List<ChatThread> _threads = const [];
  bool _loadingThreads = true;
  String? _activeThreadId;

  List<ChatMessage> _messages = const [];
  bool _loadingMessages = false;

  String _streaming = '';
  bool _sending = false;
  String? _error;

  List<ModelChoice> _models = const [];
  ModelChoice? _selectedModel;

  final List<Map<String, dynamic>> _attachments = [];
  bool _uploading = false;

  String _t(String key) => widget.translate?.call(key) ?? _en[key] ?? key;

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _loadModels();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final models = await _api.listModels();
      setState(() {
        _models = models;
        _selectedModel ??= models.firstWhere(
          (c) => c.hasKey,
          orElse: () => models.isNotEmpty ? models.first : _selectedModel!,
        );
      });
    } catch (_) {
      // Composer still works; the picker just won't show.
    }
  }

  Future<void> _loadThreads() async {
    setState(() => _loadingThreads = true);
    try {
      final threads = await _api.listThreads();
      setState(() {
        _threads = threads;
        _loadingThreads = false;
      });
      if (_activeThreadId == null && threads.isNotEmpty) {
        _selectThread(threads.first.id);
      }
    } catch (e) {
      setState(() {
        _loadingThreads = false;
        _error = '$e';
      });
    }
  }

  Future<void> _newChat() async {
    setState(() => _error = null);
    try {
      final agentId = await _api.ensureDefaultAgent();
      final thread = await _api.createThread(agentId);
      setState(() {
        _threads = [thread, ..._threads];
        _activeThreadId = thread.id;
        _messages = const [];
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _selectThread(String threadId) async {
    setState(() {
      _activeThreadId = threadId;
      _loadingMessages = true;
      _streaming = '';
      _error = null;
    });
    try {
      final msgs = await _api.listMessages(threadId);
      setState(() {
        _messages = msgs;
        _loadingMessages = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _loadingMessages = false;
        _error = '$e';
      });
    }
  }

  Future<void> _deleteThread(String threadId) async {
    try {
      await _api.deleteThread(threadId);
    } catch (_) {
      // Best-effort; the refresh reflects the true state.
    }
    if (_activeThreadId == threadId) {
      _activeThreadId = null;
      _messages = const [];
    }
    await _loadThreads();
  }

  Future<void> _pickAndAttach() async {
    final pick = widget.pickFile;
    if (pick == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final picked = await pick();
      if (picked != null) {
        final att = await _api.uploadDocument(picked);
        setState(() => _attachments.add(att));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    var threadId = _activeThreadId;
    if (threadId == null) {
      await _newChat();
      threadId = _activeThreadId;
      if (threadId == null) return;
    }
    _composer.clear();
    final attachments = List<Map<String, dynamic>>.from(_attachments);
    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(
            id: 'local-${DateTime.now().microsecondsSinceEpoch}',
            role: 'user',
            text: text),
      ];
      _attachments.clear();
      _streaming = '';
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    final model = _selectedModel;
    final buffer = StringBuffer();
    try {
      await for (final delta in _api.sendMessage(
        threadId: threadId,
        content: text,
        provider: model?.provider,
        model: model?.model,
        attachments: attachments,
      )) {
        if (delta.isError) {
          setState(() => _error = delta.error);
          break;
        }
        buffer.write(delta.text);
        setState(() => _streaming = buffer.toString());
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      final finalText = buffer.toString();
      setState(() {
        if (finalText.isNotEmpty) {
          _messages = [
            ..._messages,
            ChatMessage(
              id: 'local-a-${DateTime.now().microsecondsSinceEpoch}',
              role: 'assistant',
              text: finalText,
              modelUsed: model?.model,
            ),
          ];
        }
        _streaming = '';
        _sending = false;
      });
      _scrollToBottom();
      _loadThreads();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 260, child: _threadList(context)),
        const VerticalDivider(width: 1),
        Expanded(child: _conversation(context)),
      ],
    );
  }

  Widget _spinner([double size = 28]) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2.5),
      );

  Widget _threadList(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _newChat,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text(_t('chat.new_chat')),
            ),
          ),
        ),
        Expanded(
          child: _loadingThreads
              ? Center(child: _spinner())
              : _threads.isEmpty
                  ? Center(
                      child: Text(_t('chat.no_threads'),
                          style: Theme.of(context).textTheme.bodySmall))
                  : ListView.builder(
                      itemCount: _threads.length,
                      itemBuilder: (context, i) {
                        final t = _threads[i];
                        return ListTile(
                          selected: t.id == _activeThreadId,
                          leading:
                              const Icon(LucideIcons.messageSquare, size: 18),
                          title: Text(t.displayTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _selectThread(t.id),
                          trailing: IconButton(
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            tooltip: _t('chat.delete'),
                            onPressed: () => _deleteThread(t.id),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _conversation(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loadingMessages
              ? Center(child: _spinner(40))
              : (_messages.isEmpty && _streaming.isEmpty)
                  ? _emptyState(context)
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final m in _messages) _bubble(context, m),
                        if (_streaming.isNotEmpty)
                          _bubble(
                            context,
                            ChatMessage(
                                id: 'streaming',
                                role: 'assistant',
                                text: _streaming),
                            streaming: true,
                          ),
                      ],
                    ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer)),
          ),
        const Divider(height: 1),
        _composerBar(context),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.messagesSquare, size: 48),
          const SizedBox(height: 12),
          Text(_t('chat.empty_title'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(_t('chat.empty_hint'),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m, {bool streaming = false}) {
    final theme = Theme.of(context);
    final bg = m.isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            m.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 680),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(12)),
            child: Text(m.text.isEmpty && streaming ? '…' : m.text),
          ),
          if (!m.isUser && m.modelUsed != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text('${_t('chat.answered_by')} ${m.modelUsed}',
                  style: theme.textTheme.labelSmall),
            ),
        ],
      ),
    );
  }

  Widget _composerBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _modelPicker(context),
          if (_attachments.isNotEmpty || _uploading) ...[
            const SizedBox(height: 6),
            _attachmentChips(context),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.pickFile != null)
                IconButton(
                  onPressed: (_sending || _uploading) ? null : _pickAndAttach,
                  tooltip: _t('chat.attach'),
                  icon: _uploading
                      ? _spinner(18)
                      : const Icon(LucideIcons.paperclip, size: 18),
                ),
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 6,
                  enabled: !_sending,
                  decoration: InputDecoration(
                    hintText: _t('chat.composer_hint'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? _spinner(18)
                    : const Icon(LucideIcons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _attachmentChips(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < _attachments.length; i++)
          Chip(
            avatar: const Icon(LucideIcons.fileText, size: 14),
            label: Text(_attachments[i]['filename'] as String? ?? 'document',
                style: Theme.of(context).textTheme.labelSmall),
            onDeleted:
                _sending ? null : () => setState(() => _attachments.removeAt(i)),
          ),
        if (_uploading)
          Chip(avatar: _spinner(12), label: Text(_t('chat.attaching'))),
      ],
    );
  }

  Widget _modelPicker(BuildContext context) {
    if (_models.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(LucideIcons.cpu, size: 16),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: _selectedModel?.id,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (final c in _models)
              DropdownMenuItem<String>(
                value: c.id,
                child: Text(
                  c.hasKey
                      ? '${c.provider} · ${c.label}'
                      : '${c.provider} · ${c.label}  (${_t('chat.no_key')})',
                  style: TextStyle(
                      color:
                          c.hasKey ? null : Theme.of(context).disabledColor),
                ),
              ),
          ],
          onChanged: (id) {
            setState(() {
              _selectedModel = _models.firstWhere((c) => c.id == id,
                  orElse: () => _models.first);
            });
          },
        ),
      ],
    );
  }
}
