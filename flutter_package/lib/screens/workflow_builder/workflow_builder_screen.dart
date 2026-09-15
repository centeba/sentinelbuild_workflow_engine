import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../i18n/translate_extension.dart';
import '../../models/workflow_node.dart';
import '../../models/workflow_edge.dart';
import '../../widgets/canvas/workflow_canvas.dart';
import 'node_palette.dart';
import 'node_config_panel.dart';
// Browser-only file download; resolves to a stub off the web platform so the
// screen still compiles (and tests run) on the VM / mobile / desktop.
import 'browser_download_stub.dart'
    if (dart.library.html) 'browser_download_web.dart' as browser_download;
import '../../services/api_client.dart';
import '../../theme.dart';

class WorkflowBuilderScreen extends ConsumerStatefulWidget {
  final String? workflowId;
  /// Vertical-app ownership tag stamped on workflows created here.
  /// ``null`` (chassis default) → generic platform workflow; a value
  /// like ``'restoration'`` tags the workflow to that app so it only
  /// surfaces in that app's list. Mirrors ``WorkflowsScreen.sourceApp``.
  final String? sourceApp;
  const WorkflowBuilderScreen({
    super.key,
    required this.workflowId,
    this.sourceApp,
  });
  @override
  ConsumerState<WorkflowBuilderScreen> createState() => _WorkflowBuilderScreenState();
}

class _WorkflowBuilderScreenState extends ConsumerState<WorkflowBuilderScreen> {
  final _uuid = const Uuid();
  List<WorkflowNode> _nodes = [];
  List<WorkflowEdge> _edges = [];
  WorkflowNode? _selectedNode;
  String _name = 'Untitled Workflow';
  bool _saving = false;
  bool _loadingPinned = false;

  // Gap 7: pinned outputs from last run {nodeId: outputData}
  Map<String, Map<String, dynamic>> _pinnedOutputs = {};

  @override
  void initState() {
    super.initState();
    if (widget.workflowId != null) _loadWorkflow();
  }

  Future<void> _loadWorkflow() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/workflows/${widget.workflowId}');
      if (!mounted) return;
      final def = (resp.data['definition'] as Map?)?.cast<String, dynamic>()
          ?? const <String, dynamic>{};
      final rawNodes = (def['nodes'] as List?) ?? const [];
      final rawEdges = (def['edges'] as List?) ?? const [];
      final loadedNodes = rawNodes
          .map((n) => WorkflowNode.fromJson(n as Map<String, dynamic>))
          .toList();
      // If every node landed at (0,0) — usually because the workflow
      // was seeded/imported without builder positions — spread them
      // along a horizontal row so the user sees the DAG instead of a
      // single overlapping stack at the origin.
      final needsAutoLayout = loadedNodes.isNotEmpty &&
          loadedNodes.every((n) =>
              n.position.dx == 0.0 && n.position.dy == 0.0);
      final nodes = needsAutoLayout
          ? [
              for (var i = 0; i < loadedNodes.length; i++)
                loadedNodes[i].copyWith(
                  position: Offset(120.0 + i * 220.0, 200.0),
                )
            ]
          : loadedNodes;
      setState(() {
        _name = resp.data['name'] as String? ?? _name;
        _nodes = nodes;
        _edges = rawEdges
            .map((e) => WorkflowEdge.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      // Surface a snackbar instead of silently rendering blank. The
      // previous code let parsing errors escape into the void.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load workflow: $e')),
      );
    }
  }

  // ── Gap 7: Pin output from last run ───────────────────────────────────────

  Future<void> _loadPinnedOutputs() async {
    if (widget.workflowId == null) return;
    setState(() => _loadingPinned = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/workflows/${widget.workflowId}/last-run-outputs');
      final raw = resp.data as Map<String, dynamic>;
      setState(() {
        _pinnedOutputs = {
          for (final e in raw.entries)
            e.key: Map<String, dynamic>.from(e.value as Map? ?? {}),
        };
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pinned outputs from last run (${_pinnedOutputs.length} nodes)')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('workflow_builder.no_previous_run'))),
        );
      }
    } finally {
      setState(() => _loadingPinned = false);
    }
  }

  void _clearPinnedOutputs() => setState(() => _pinnedOutputs = {});

  // ── Gap 10: Import / Export ───────────────────────────────────────────────

  Future<void> _exportWorkflow() async {
    if (widget.workflowId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('workflow_builder.save_before_export'))),
      );
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/workflows/${widget.workflowId}/export');
      final jsonStr = const JsonEncoder.withIndent('  ').convert(resp.data);
      // Download via browser anchor element (Flutter Web)
      _downloadJson(jsonStr, '${_name.replaceAll(' ', '_').toLowerCase()}.workflow.json');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _downloadJson(String content, String filename) {
    // Flutter Web: trigger a browser download. Off web this throws and we fall
    // back to showing the JSON in a copyable dialog.
    try {
      browser_download.downloadText(content, filename,
          mimeType: 'application/json');
    } catch (_) {
      // Non-web: show the JSON in a dialog so the user can copy it
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${ctx.t('workflow_builder.export_prefix')}: $filename',
              style: const TextStyle(color: AppTheme.textBright)),
          content: SizedBox(
            width: 600,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.codeText)),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('common.close')))],
        ),
      );
    }
  }

  Future<void> _showImportDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (result == null || result.isEmpty) return;
    try {
      final data = json.decode(result) as Map<String, dynamic>;
      final dio = ref.read(dioProvider);
      // Capture localized prefix BEFORE the await for safe context use.
      final tImported = context.t('workflow_builder.imported_prefix');
      final resp = await dio.post('/workflows/import', data: data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tImported "${resp.data["name"]}"')),
        );
        Navigator.of(context).pop(); // go back to workflows list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.t('workflow_builder.import_failed_prefix')}: $e')));
      }
    }
  }

  // ── Canvas mutations ──────────────────────────────────────────────────────

  void _addNode(String type, [Map<String, dynamic>? initialConfig]) {
    // Cascade newly-added nodes so they don't stack on one spot. Step
    // diagonally, wrapping every 8 so a long workflow stays on-canvas.
    final i = _nodes.length;
    final pos = Offset(160 + (i % 8) * 80.0, 120 + (i % 8) * 70.0);
    setState(() => _nodes = [..._nodes, WorkflowNode(
      id: _uuid.v4(),
      type: type,
      name: '',
      position: pos,
      config: initialConfig ?? const {},
    )]);
  }

  void _updateNodePosition(String nodeId, Offset pos) {
    setState(() => _nodes = _nodes.map((n) => n.id == nodeId ? n.copyWith(position: pos) : n).toList());
  }

  Future<void> _addEdge(String from, String to) async {
    if (_edges.any((e) => e.from == from && e.to == to)) return;
    // Branch-producing nodes route differently per outgoing edge, so
    // ask which branch this connection represents. Other node types
    // create an unconditional edge as before.
    final src = _nodes.firstWhere(
      (n) => n.id == from,
      orElse: () => WorkflowNode(
        id: from, type: '', name: '', position: Offset.zero, config: const {},
      ),
    );
    String? branch;
    if (src.type == 'if_condition' || src.type == 'wait_approval') {
      // Edge branch values the executor matches: "true" → true_branch,
      // "false" → false_branch (see workflow_executor._is_edge_live).
      final picked = await _pickBranchLabel(
        title: src.type == 'wait_approval'
            ? 'When the approval is…'
            : 'When the condition is…',
        options: const [
          ('true', 'True'),
          ('false', 'False'),
          ('', 'Always (no condition)'),
        ],
      );
      if (picked == null) return; // cancelled
      branch = picked.isEmpty ? null : picked;
    } else if (src.type == 'switch') {
      final label = await _promptText(
        'Switch case value',
        'e.g. gold  (or "default")',
      );
      if (label == null) return; // cancelled
      branch = label.trim().isEmpty ? null : label.trim();
    }
    setState(() => _edges = [
          ..._edges,
          WorkflowEdge(from: from, to: to, branch: branch),
        ]);
  }

  /// Modal to pick a branch label for an edge leaving a branching node.
  /// Returns the chosen value, or null if the user cancelled.
  Future<String?> _pickBranchLabel({
    required String title,
    required List<(String, String)> options,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, value),
              child: Text(label),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Single-line text prompt. Returns entered text, or null if cancelled.
  Future<String?> _promptText(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _deleteNode(String nodeId) {
    setState(() {
      _nodes = _nodes.where((n) => n.id != nodeId).toList();
      _edges = _edges.where((e) => e.from != nodeId && e.to != nodeId).toList();
      if (_selectedNode?.id == nodeId) _selectedNode = null;
      _pinnedOutputs.remove(nodeId);
    });
  }

  void _updateNodeConfig(Map<String, dynamic> config) {
    if (_selectedNode == null) return;
    setState(() {
      _nodes = _nodes.map((n) => n.id == _selectedNode!.id ? n.copyWith(config: config) : n).toList();
      _selectedNode = _selectedNode!.copyWith(config: config);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final definition = {
        'nodes': _nodes.map((n) => n.toJson()).toList(),
        'edges': _edges.map((e) => e.toJson()).toList(),
      };
      if (widget.workflowId == null) {
        await dio.post('/workflows', data: {
          'name': _name,
          'definition': definition,
          // Stamp the owning app on create so the workflow only shows in
          // that app's list. Omitted when null → generic platform workflow.
          if (widget.sourceApp != null) 'source_app': widget.sourceApp,
        });
      } else {
        // source_app is immutable post-create — not sent on update.
        await dio.put('/workflows/${widget.workflowId}', data: {'name': _name, 'definition': definition});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t('workflow_builder.saved'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _run() async {
    // Need a saved workflow to execute. If this is an unsaved draft, save
    // first (creates the workflow) — the user can then press Run again.
    if (widget.workflowId == null) { await _save(); return; }
    final dio = ref.read(dioProvider);
    String? executionId;
    try {
      final resp =
          await dio.post('/workflows/${widget.workflowId}/execute', data: {});
      executionId = resp.data['execution_id']?.toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('${context.t('common.request_failed')}: $e'),
        ));
      }
      return;
    }
    if (executionId == null || !mounted) return;
    // Open a live results panel that polls the execution + per-node results
    // until the run reaches a terminal state.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RunResultsSheet(dio: dio, executionId: executionId!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPage,
      body: Column(children: [
        _Toolbar(
          name: _name,
          onNameChanged: (v) => setState(() => _name = v),
          onSave: _save,
          onRun: _run,
          onExport: _exportWorkflow,
          onImport: _showImportDialog,
          onLoadPinnedOutputs: widget.workflowId != null ? _loadPinnedOutputs : null,
          onClearPinned: _pinnedOutputs.isNotEmpty ? _clearPinnedOutputs : null,
          saving: _saving,
          loadingPinned: _loadingPinned,
          hasPinnedOutputs: _pinnedOutputs.isNotEmpty,
        ),
        Expanded(
          child: Row(children: [
            NodePalette(onNodeSelected: _addNode),
            Expanded(
              child: WorkflowCanvas(
                nodes: _nodes,
                edges: _edges,
                selectedNode: _selectedNode,
                pinnedOutputs: _pinnedOutputs,
                onNodeSelected: (n) => setState(() => _selectedNode = n),
                onNodeMoved: _updateNodePosition,
                onEdgeCreated: _addEdge,
                onNodeDeleted: _deleteNode,
              ),
            ),
            if (_selectedNode != null)
              _NodePanel(
                node: _selectedNode!,
                pinnedOutput: _pinnedOutputs[_selectedNode!.id],
                onConfigChanged: _updateNodeConfig,
                onClose: () => setState(() => _selectedNode = null),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ── Node config panel wrapper with pinned output section ─────────────────────

class _NodePanel extends StatelessWidget {
  final WorkflowNode node;
  final Map<String, dynamic>? pinnedOutput;
  final void Function(Map<String, dynamic>) onConfigChanged;
  final VoidCallback onClose;

  const _NodePanel({
    required this.node,
    required this.pinnedOutput,
    required this.onConfigChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: NodeConfigPanel(
            node: node,
            onConfigChanged: onConfigChanged,
            onClose: onClose,
          ),
        ),
        if (pinnedOutput != null && pinnedOutput!.isNotEmpty)
          _PinnedOutputPanel(output: pinnedOutput!),
      ],
    );
  }
}

class _PinnedOutputPanel extends StatelessWidget {
  final Map<String, dynamic> output;
  const _PinnedOutputPanel({required this.output});

  @override
  Widget build(BuildContext context) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(output);
    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: const BoxDecoration(
        color: AppTheme.bgRaised,
        border: Border(top: BorderSide(color: Color(0xFF22C55E), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              const Icon(Icons.push_pin, size: 12, color: Color(0xFF22C55E)),
              const SizedBox(width: 6),
              Text(context.t('workflow_builder.pinned_output'),
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: Color(0xFF22C55E), letterSpacing: 0.6)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                jsonStr,
                style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: AppTheme.codeText),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends StatefulWidget {
  final String name;
  final void Function(String) onNameChanged;
  final VoidCallback onSave;
  final VoidCallback onRun;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback? onLoadPinnedOutputs;
  final VoidCallback? onClearPinned;
  final bool saving;
  final bool loadingPinned;
  final bool hasPinnedOutputs;

  const _Toolbar({
    required this.name,
    required this.onNameChanged,
    required this.onSave,
    required this.onRun,
    required this.onExport,
    required this.onImport,
    this.onLoadPinnedOutputs,
    this.onClearPinned,
    required this.saving,
    required this.loadingPinned,
    required this.hasPinnedOutputs,
  });

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
  }

  @override
  void didUpdateWidget(covariant _Toolbar old) {
    super.didUpdateWidget(old);
    // Only sync when the parent's name actually changed AND differs from
    // the in-flight text (e.g. after _load() pulled a saved workflow).
    // Never clobber the user's keystrokes — that's what produced the
    // reverse-letter bug.
    if (widget.name != old.name && widget.name != _nameCtrl.text) {
      _nameCtrl.text = widget.name;
      _nameCtrl.selection = TextSelection.collapsed(offset: widget.name.length);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSave            = widget.onSave;
    final onRun             = widget.onRun;
    final onExport          = widget.onExport;
    final onImport          = widget.onImport;
    final onLoadPinnedOutputs = widget.onLoadPinnedOutputs;
    final onClearPinned     = widget.onClearPinned;
    final saving            = widget.saving;
    final loadingPinned     = widget.loadingPinned;
    final hasPinnedOutputs  = widget.hasPinnedOutputs;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.bgRaised,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(children: [
        InkWell(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back, size: 20, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 240,
          child: TextField(
            controller: _nameCtrl,
            onChanged: widget.onNameChanged,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textBright),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, fillColor: Colors.transparent),
          ),
        ),
        const Spacer(),

        // Gap 7: Pin / clear pinned output
        if (hasPinnedOutputs)
          IconButton(
            onPressed: onClearPinned,
            icon: const Icon(Icons.push_pin, size: 16, color: Color(0xFF22C55E)),
            tooltip: context.t('workflow_builder.clear_pinned'),
          )
        else if (onLoadPinnedOutputs != null)
          IconButton(
            onPressed: loadingPinned ? null : onLoadPinnedOutputs,
            icon: loadingPinned
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.push_pin_outlined, size: 16, color: AppTheme.textSecondary),
            tooltip: context.t('workflow_builder.pin_last_outputs'),
          ),

        // Gap 10: Import / Export
        PopupMenuButton<String>(
          onSelected: (v) => v == 'export' ? onExport() : onImport(),
          color: AppTheme.bgRaised,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              Icon(Icons.import_export, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 4),
              // Format identifier — kept untranslated
              Text('JSON', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ]),
          ),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'export', child: Row(children: [
              const Icon(Icons.file_download_outlined, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(context.t('workflow_builder.export_workflow'),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ])),
            PopupMenuItem(value: 'import', child: Row(children: [
              const Icon(Icons.file_upload_outlined, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(context.t('workflow_builder.import_workflow'),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ])),
          ],
        ),

        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textSecondary))
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(context.t('common.save')),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onRun,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: Text(context.t('common.run')),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.successBorder),
        ),
      ]),
    );
  }
}

// ── Import dialog ─────────────────────────────────────────────────────────────

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _submit() {
    try {
      final parsed = json.decode(_ctrl.text);
      if (parsed is! Map || parsed['mit_stack_export_version'] != '1.0') {
        setState(() => _error = context.t('workflow_builder.invalid_format'));
        return;
      }
      Navigator.pop(context, _ctrl.text);
    } catch (_) {
      setState(() => _error = context.t('workflow_builder.invalid_json'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('workflow_builder.import_dialog_title'),
          style: const TextStyle(color: AppTheme.textBright)),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('workflow_builder.paste_export_json'),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.codeText),
            // Hint is example JSON — kept literal.
            decoration: const InputDecoration(hintText: '{"mit_stack_export_version": "1.0", ...}'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppTheme.errorText, fontSize: 12)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('common.cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.t('workflow_builder.import_button'))),
      ],
    );
  }
}

// ── Run results sheet ────────────────────────────────────────────────────────
// Opened after the Run button fires. Polls the execution + per-node results
// until the run reaches a terminal state, then shows the workflow output and
// each step's output / error so the builder can see *what the run produced*
// (and why it failed) without leaving the canvas.

const _kTerminalStatuses = {'completed', 'failed', 'cancelled', 'error'};

class _RunResultsSheet extends StatefulWidget {
  final Dio dio;
  final String executionId;
  const _RunResultsSheet({required this.dio, required this.executionId});

  @override
  State<_RunResultsSheet> createState() => _RunResultsSheetState();
}

class _RunResultsSheetState extends State<_RunResultsSheet> {
  Map<String, dynamic>? _exec;
  List<Map<String, dynamic>> _nodes = const [];
  String? _error;
  Timer? _timer;
  int _polls = 0;
  // ~2 min ceiling (100 x 1.2s) so a stuck / awaiting-approval run doesn't
  // poll forever; the user can re-open from the executions list if needed.
  static const _maxPolls = 100;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer =
        Timer.periodic(const Duration(milliseconds: 1200), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isTerminal {
    final s = (_exec?['status'] as String?) ?? '';
    return _kTerminalStatuses.contains(s);
  }

  Future<void> _poll() async {
    if (!mounted) return;
    _polls++;
    try {
      final execResp =
          await widget.dio.get('/executions/${widget.executionId}');
      final nodesResp =
          await widget.dio.get('/executions/${widget.executionId}/nodes');
      if (!mounted) return;
      setState(() {
        _exec = (execResp.data as Map).cast<String, dynamic>();
        _nodes = ((nodesResp.data as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (_isTerminal || _polls >= _maxPolls) {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (_exec?['status'] as String?) ?? 'running';
    final running = !_isTerminal;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgPage,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Text('Run results',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textBright)),
                    const SizedBox(width: 10),
                    _StatusPill(status: status),
                    if (running) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: _buildBody(status),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(String status) {
    final exec = _exec;
    final children = <Widget>[];

    if (exec == null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            _error ?? 'Starting...',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
      ));
      return children;
    }

    final err = (exec['error_message'] as String?)?.trim();
    if (err != null && err.isNotEmpty) {
      children.add(_ErrorBox(message: err));
      children.add(const SizedBox(height: 12));
    }

    final output = (exec['output_data'] as Map?)?.cast<String, dynamic>();
    if (output != null && output.isNotEmpty) {
      children.add(const _SectionLabel('WORKFLOW OUTPUT'));
      children.add(const SizedBox(height: 6));
      children.add(_JsonBlock(value: output));
      children.add(const SizedBox(height: 16));
    }

    children.add(_SectionLabel('STEPS (${_nodes.length})'));
    children.add(const SizedBox(height: 6));
    if (_nodes.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No step results yet.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ));
    } else {
      for (final n in _nodes) {
        children.add(_NodeResultTile(node: n));
      }
    }

    if ((output == null || output.isEmpty) &&
        _isTerminal &&
        status == 'completed') {
      children.add(const SizedBox(height: 12));
      children.add(const Text('Workflow completed (no output payload).',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
    }
    return children;
  }
}

/// Status -> (bg, fg) colours, shared by the header pill + node tiles.
(Color, Color) _statusColors(String status) {
  switch (status) {
    case 'completed':
      return (AppTheme.successBg, AppTheme.successBorder);
    case 'failed':
    case 'error':
      return (AppTheme.errorBg, AppTheme.errorBorder);
    case 'cancelled':
      return (AppTheme.warningBg, const Color(0xFFB45309));
    case 'running':
    case 'pending':
    default:
      return (AppTheme.infoBg, const Color(0xFF1D4ED8));
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style:
            TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: AppTheme.textMuted),
      );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorBg,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppTheme.errorBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              size: 16, color: AppTheme.errorBorder),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: const TextStyle(
                  color: AppTheme.errorBorder, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final Object value;
  const _JsonBlock({required this.value});
  @override
  Widget build(BuildContext context) {
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      text = value.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            color: AppTheme.codeText),
      ),
    );
  }
}

class _NodeResultTile extends StatelessWidget {
  final Map<String, dynamic> node;
  const _NodeResultTile({required this.node});

  @override
  Widget build(BuildContext context) {
    final status = (node['status'] as String?) ?? 'unknown';
    final (_, fg) = _statusColors(status);
    final nodeType = (node['node_type'] as String?) ?? 'node';
    final nodeId = (node['node_id'] as String?) ?? '';
    final output = (node['output_data'] as Map?)?.cast<String, dynamic>();
    final err = (node['error_message'] as String?)?.trim();
    final hasDetail = (output != null && output.isNotEmpty) ||
        (err != null && err.isNotEmpty);

    final header = Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            nodeType,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textBright),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _StatusPill(status: status),
      ],
    );

    final detailChildren = <Widget>[
      if (nodeId.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 18, top: 2, bottom: 6),
          child: Text(nodeId,
              style: const TextStyle(
                  fontSize: 10.5, color: AppTheme.textMuted)),
        ),
      if (err != null && err.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 8),
          child: _ErrorBox(message: err),
        ),
      if (output != null && output.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 8),
          child: _JsonBlock(value: output),
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border:
            Border.all(color: AppTheme.textMuted.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: hasDetail
          ? Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: header,
                children: detailChildren,
              ),
            )
          : Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: header,
            ),
    );
  }
}
