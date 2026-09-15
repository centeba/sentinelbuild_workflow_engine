// Phase-E3 close-out — admin "Try it" panel.
//
// The streaming infrastructure has been in place for a while:
//
//   - Backend: `/ws/ai-agents/{agent_id}/stream` (smart-llm router)
//     yields `{delta: "..."}` chunks then `{done: true}` over a
//     WebSocket. Auth = JWT in the first message frame.
//   - Dart client: `screens/ai_admin/agent_stream.dart` exposes
//     `AgentStream.tokens()` and an `agentStreamProvider`
//     `StreamProvider.family` that emits cumulative text.
//
// What was missing: a UI surface so admins could actually exercise
// the stream against an agent they just edited. This dialog is that
// surface — opened from the play (▶) action on each agent row in the
// Agents tab.
//
// Why a dialog and not a full screen: the workflow run-history
// viewer renders an agent_node's persisted result statically; it's
// not the right place for an interactive Try-It. Power users want a
// quick way to validate an edit ("did my system_prompt change
// actually fix the JSON shape?") — a dialog with input + streamed
// output gives that without committing to a route.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'agent_stream.dart';

/// Opens the Try-It dialog for ``agent``. The dialog manages its own
/// stream subscription via Riverpod and unsubscribes when closed.
Future<void> showAgentTryDialog(
  BuildContext context, {
  required Map<String, dynamic> agent,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AgentTryDialog(agent: agent),
    );

class AgentTryDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> agent;
  const AgentTryDialog({super.key, required this.agent});

  @override
  ConsumerState<AgentTryDialog> createState() => _AgentTryDialogState();
}

class _AgentTryDialogState extends ConsumerState<AgentTryDialog> {
  final _inputCtrl = TextEditingController();

  /// Family-arg for the active subscription. Setting this to a fresh
  /// `(agentId, input)` triggers a new run; setting it to `null`
  /// stops the stream (Riverpod auto-disposes the provider).
  ({String agentId, String input})? _runArgs;

  String get _agentId => widget.agent['id'].toString();
  String get _agentLabel =>
      (widget.agent['label'] as String?) ??
      (widget.agent['name'] as String? ?? 'Agent');

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _run() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    // Force a new stream by replacing the family arg. If the user
    // hits Run twice with identical input, we vary by re-issuing the
    // same record — Riverpod treats it as the same family key and
    // returns the cached result, which is fine for this UX (cached
    // text simply re-renders instantly).
    setState(() => _runArgs = (agentId: _agentId, input: text));
  }

  void _stop() {
    setState(() => _runArgs = null);
  }

  @override
  Widget build(BuildContext context) {
    final args = _runArgs;
    return AlertDialog(
      backgroundColor: AppTheme.bgSurface,
      title: Row(children: [
        const Icon(LucideIcons.play, size: 18, color: AppTheme.primaryText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('ai_admin.try_it.title'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textBright,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _agentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _inputCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.t('ai_admin.try_it.input_label'),
                hintText: context.t('ai_admin.try_it.input_hint'),
                hintStyle: const TextStyle(color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            // Output panel — fixed-height box with streamed text.
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: AppTheme.bgRaised,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              padding: const EdgeInsets.all(12),
              child: args == null
                  ? Center(
                      child: Text(
                        context.t('ai_admin.try_it.idle'),
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12),
                      ),
                    )
                  : _StreamView(args: args),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: args != null ? _stop : null,
          child: Text(context.t('ai_admin.try_it.stop')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('common.close')),
        ),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.play_arrow, size: 14),
          label: Text(context.t('ai_admin.try_it.run')),
        ),
      ],
    );
  }
}

/// Inner view that holds the active subscription. Split out so the
/// surrounding dialog widget rebuilds cheaply on input changes
/// without re-watching the stream provider.
class _StreamView extends ConsumerWidget {
  final ({String agentId, String input}) args;
  const _StreamView({required this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(agentStreamProvider(args));
    return async.when(
      // The provider emits cumulative text every chunk, so ``data``
      // is the running output. The wait-state happens only when the
      // WebSocket is still connecting — typically a single frame.
      data: (text) => SingleChildScrollView(
        reverse: true,
        child: Text(
          text.isEmpty ? '…' : text,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textPrimary,
            height: 1.4,
          ),
        ),
      ),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (err, _) => SingleChildScrollView(
        child: Text(
          'Error: $err',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.errorText,
          ),
        ),
      ),
    );
  }
}
