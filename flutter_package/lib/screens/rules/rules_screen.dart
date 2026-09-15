import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../i18n/translate_extension.dart';
import '../../services/api_client.dart';
import '../../theme.dart';
import '../../constants.dart';
import '../../widgets/common/ai_search_bar.dart';
import '../workflow_builder/node_type_registry.dart';
import '../workflow_builder/schema_condition_builder.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  List<Map<String, dynamic>> _rules = [];
  List<Map<String, dynamic>>? _aiRows; // Phase H — when set, render these
  bool _loading = true;
  String _statusFilter = 'all'; // 'all' | 'draft' | 'published'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final params = _statusFilter != 'all' ? {'status': _statusFilter} : null;
      final resp = await dio.get('/rules', queryParameters: params);
      setState(() {
        _rules = List<Map<String, dynamic>>.from(resp.data as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> rule) async {
    final dio = ref.read(dioProvider);
    await dio.put('/rules/${rule['id']}', data: {'is_active': !(rule['is_active'] as bool)});
    _load();
  }

  Future<void> _publishRule(Map<String, dynamic> rule) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/rules/${rule['id']}/publish');
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                '${context.t('rules.rule_label')} "${rule['name']}" ${context.t('rules.published_suffix')}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.t('common.error_prefix')}: $e'),
                backgroundColor: AppTheme.errorBorder));
      }
    }
  }

  Future<void> _unpublishRule(Map<String, dynamic> rule) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/rules/${rule['id']}/unpublish');
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                '${context.t('rules.rule_label')} "${rule['name']}" ${context.t('rules.moved_to_draft_suffix')}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.t('common.error_prefix')}: $e'),
                backgroundColor: AppTheme.errorBorder));
      }
    }
  }

  void _showAnalytics(Map<String, dynamic> rule) => showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.bgSurface,
        isScrollControlled: true,
        builder: (_) => _AnalyticsSheet(
          ruleId: rule['id'] as String,
          ruleName: rule['name'] as String? ?? '',
        ),
      );

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: Text(ctx.t('rules.delete_title'),
            style: const TextStyle(color: AppTheme.textBright)),
        content: Text(ctx.t('common.cannot_be_undone'),
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('common.cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorBorder),
            child: Text(ctx.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final dio = ref.read(dioProvider);
      await dio.delete('/rules/$id');
      _load();
    }
  }

  void _openEditor({Map<String, dynamic>? rule}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RuleEditorDialog(rule: rule),
    );
    if (result == true) _load();
  }

  void _testRule(Map<String, dynamic> rule) => showDialog(
        context: context,
        builder: (_) => _TestRuleDialog(ruleId: rule['id'] as String),
      );

  void _showVersionHistory(Map<String, dynamic> rule) => showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.bgSurface,
        isScrollControlled: true,
        builder: (_) => _VersionHistorySheet(
          ruleId: rule['id'] as String,
          ruleName: rule['name'] as String? ?? '',
          onRestored: _load,
        ),
      );

  void _showPendingApprovals() => showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.bgSurface,
        isScrollControlled: true,
        builder: (_) => _PendingApprovalsSheet(onApproved: _load),
      );

  Future<void> _requestApproval(Map<String, dynamic> rule) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/rules/${rule['id']}/request-approval');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              '${context.t('rules.approval_requested_prefix')} "${rule['name']}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.t('common.error_prefix')}: $e'),
              backgroundColor: AppTheme.errorBorder),
        );
      }
    }
  }

  void _showAuditLog(Map<String, dynamic> rule) => showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.bgSurface,
        isScrollControlled: true,
        builder: (_) => _AuditLogSheet(
          ruleId: rule['id'] as String,
          ruleName: rule['name'] as String? ?? '',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPage,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('rules.title'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textBright)),
                const SizedBox(height: 4),
                Text(context.t('rules.subtitle'),
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ]),
            ),
            // Status filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgRaised,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: DropdownButton<String>(
                value: _statusFilter,
                underline: const SizedBox(),
                isDense: true,
                dropdownColor: AppTheme.bgRaised,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                items: [
                  DropdownMenuItem(value: 'all',       child: Text(context.t('rules.filter_all'))),
                  DropdownMenuItem(value: 'published', child: Text(context.t('rules.published'))),
                  DropdownMenuItem(value: 'draft',     child: Text(context.t('rules.draft'))),
                ],
                onChanged: (v) => setState(() {
                  _statusFilter = v!;
                  _load();
                }),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _showPendingApprovals,
              icon: const Icon(Icons.approval_outlined, size: 14, color: AppTheme.warningText),
              label: Text(context.t('rules.approvals'),
                  style: const TextStyle(color: AppTheme.warningText, fontSize: 13)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.warningBorder)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.t('rules.new_rule')),
            ),
          ]),
          const SizedBox(height: 8),
          // Info banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.infoBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.infoBorder),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: AppTheme.infoText),
              const SizedBox(width: 8),
              Expanded(child: Text(
                context.t('rules.info_banner'),
                style: const TextStyle(fontSize: 12, color: AppTheme.infoText),
              )),
            ]),
          ),
          const SizedBox(height: 16),
          AiSearchBar(
            entity: 'rules',
            onResults: (rows) => setState(() => _aiRows = rows),
            onClear: () => setState(() => _aiRows = null),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildRulesBody()),
        ]),
      ),
    );
  }

  Widget _buildRulesBody() {
    final list = _aiRows ?? _rules;
    if (_loading && _aiRows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.rule_outlined, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 8),
          Text(context.t('rules.empty_title'), style: const TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add, size: 14),
            label: Text(context.t('rules.create_first')),
          ),
        ]),
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
          child: DataTable(
            border: TableBorder.all(color: AppTheme.borderStrong, width: 1),
            headingRowColor: const WidgetStatePropertyAll(AppTheme.bgRaised),
            headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textBright),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Priority'), numeric: true),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Events')),
              DataColumn(label: Text('Logic')),
              DataColumn(label: Text('Active')),
              DataColumn(label: Text('Actions')),
            ],
            rows: list.map(_ruleRow).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _ruleRow(Map<String, dynamic> rule) {
    final isActive = rule['is_active'] as bool? ?? true;
    final status = rule['status'] as String? ?? 'published';
    final ruleType = rule['rule_type'] as String? ?? 'condition_tree';
    final isPublished = status == 'published';
    final approvalRequired = rule['approval_required'] as bool? ?? false;
    final events = (rule['trigger_events'] as List?)?.cast<String>() ?? [];
    final actions = (rule['actions'] as List?)?.cast<Map>() ?? [];
    final conditions = rule['conditions'] as Map? ?? {};
    final condCount = ruleType == 'decision_table'
        ? (conditions['rows'] as List?)?.length ?? 0
        : ruleType == 'javascript'
            ? ((conditions['code'] as String?)?.isNotEmpty ?? false ? 1 : 0)
            : (conditions['rules'] as List?)?.length ?? 0;
    return DataRow(cells: [
      DataCell(Text('${rule['priority'] ?? 100}')),
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(rule['name'] as String? ?? 'Unnamed Rule',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppTheme.textBright : AppTheme.textMuted)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: AppTheme.pill(
              bg: isPublished ? AppTheme.successBg : AppTheme.warningBg,
              border:
                  isPublished ? AppTheme.successBorder : AppTheme.warningBorder,
            ),
            child: Text(isPublished ? 'published' : 'draft',
                style: TextStyle(
                    fontSize: 10,
                    color: isPublished
                        ? AppTheme.successText
                        : AppTheme.warningText)),
          ),
        ]),
      )),
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
            events.isEmpty ? '—' : events.map(_labelForEvent).join(', '),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textSecondary)),
      )),
      DataCell(Text('$condCount cond · ${actions.length} act',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))),
      DataCell(Switch(value: isActive, onChanged: (_) => _toggleActive(rule))),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        // Primary actions stay as direct icons; everything else lives in the
        // overflow menu so the row stays compact.
        _IconBtn(
            isPublished ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
            isPublished ? AppTheme.textMuted : AppTheme.successText,
            isPublished ? () => _unpublishRule(rule) : () => _publishRule(rule),
            isPublished ? context.t('rules.move_to_draft') : context.t('rules.publish')),
        _IconBtn(Icons.edit_outlined, AppTheme.textSecondary,
            () => _openEditor(rule: rule), context.t('common.edit')),
        _IconBtn(Icons.delete_outline, AppTheme.errorText,
            () => _delete(rule['id'] as String), context.t('common.delete')),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert,
              size: 18, color: AppTheme.textSecondary),
          onSelected: (v) {
            switch (v) {
              case 'test':
                _testRule(rule);
              case 'approval':
                _requestApproval(rule);
              case 'history':
                _showVersionHistory(rule);
              case 'analytics':
                _showAnalytics(rule);
              case 'audit':
                _showAuditLog(rule);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'test',
                child: _menuItem(Icons.science_outlined, context.t('rules.test'))),
            if (approvalRequired && !isPublished)
              PopupMenuItem(
                  value: 'approval',
                  child: _menuItem(Icons.approval_outlined,
                      context.t('rules.request_approval'))),
            PopupMenuItem(
                value: 'history',
                child: _menuItem(
                    Icons.history, context.t('rules.version_history'))),
            PopupMenuItem(
                value: 'analytics',
                child: _menuItem(
                    Icons.analytics_outlined, context.t('rules.analytics'))),
            PopupMenuItem(
                value: 'audit',
                child: _menuItem(
                    Icons.bar_chart_outlined, context.t('rules.audit_log'))),
          ],
        ),
      ])),
    ]);
  }
}

// ─── Rule helpers ─────────────────────────────────────────────────────────────

String _labelForEvent(String v) =>
    kTriggerEvents.firstWhere((e) => e['value'] == v,
        orElse: () => {'label': v})['label'] as String;

/// Icon + label row used inside the Rules row overflow menu.
Widget _menuItem(IconData icon, String label) => Row(children: [
      Icon(icon, size: 16, color: AppTheme.textSecondary),
      const SizedBox(width: 10),
      Text(label),
    ]);

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  const _IconBtn(this.icon, this.color, this.onTap, this.tooltip);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      );
}

// ─── Rule editor dialog ───────────────────────────────────────────────────────

class _RuleEditorDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? rule;
  const _RuleEditorDialog({this.rule});

  @override
  ConsumerState<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<_RuleEditorDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  // Basics
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController();
  bool _isActive = true;
  bool _stopOnMatch = false;
  bool _approvalRequired = false;
  final _approversCtrl = TextEditingController();
  String _status = 'draft';
  String _ruleType = 'condition_tree';
  // Version note (PUT only)
  final _versionNoteCtrl = TextEditingController();
  // Triggers
  Set<String> _selectedEvents = {};
  final _filterKeyCtrl = TextEditingController();
  final _filterValCtrl = TextEditingController();
  Map<String, String> _triggerFilter = {};
  // Conditions (JSON tree) — also stores decision table / JS code structure
  Map<String, dynamic> _conditions = {'combinator': 'and', 'rules': []};
  // Gap 11: JS code (stored in conditions.code)
  final _jsCodeCtrl = TextEditingController();
  // Actions (then + else) — not used for decision_table
  List<Map<String, dynamic>> _actions = [];
  List<Map<String, dynamic>> _elseActions = [];
  bool _saving = false;
  final bool _aiGenerating = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    final r = widget.rule;
    if (r != null) {
      _nameCtrl.text = r['name'] ?? '';
      _descCtrl.text = r['description'] ?? '';
      _priorityCtrl.text = (r['priority'] ?? 100).toString();
      _isActive = r['is_active'] ?? true;
      _stopOnMatch = r['stop_on_match'] ?? false;
      _approvalRequired = r['approval_required'] as bool? ?? false;
      final approvers = (r['required_approvers'] as List?)?.cast<String>() ?? [];
      _approversCtrl.text = approvers.join(', ');
      _status = r['status'] as String? ?? 'published';
      _ruleType = r['rule_type'] as String? ?? 'condition_tree';
      _selectedEvents = Set<String>.from((r['trigger_events'] as List?) ?? []);
      _triggerFilter = Map<String, String>.from(
          (r['trigger_filter'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {});
      _conditions = Map<String, dynamic>.from(r['conditions'] as Map? ?? {'combinator': 'and', 'rules': []});
      if (_ruleType == 'javascript') {
        _jsCodeCtrl.text = _conditions['code'] as String? ?? '';
      }
      _actions = List<Map<String, dynamic>>.from(
          (r['actions'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ?? []);
      _elseActions = List<Map<String, dynamic>>.from(
          (r['else_actions'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ?? []);
    } else {
      _priorityCtrl.text = '100';
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priorityCtrl.dispose();
    _approversCtrl.dispose();
    _jsCodeCtrl.dispose();
    _filterKeyCtrl.dispose();
    _filterValCtrl.dispose();
    _versionNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rule name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      // Build conditions: for JS rules, embed the code in conditions dict
      final conditions = _ruleType == 'javascript'
          ? {'code': _jsCodeCtrl.text}
          : _conditions;

      // Parse approvers from comma-separated text
      final approversList = _approversCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'priority': int.tryParse(_priorityCtrl.text) ?? 100,
        'is_active': _isActive,
        'stop_on_match': _stopOnMatch,
        'status': _status,
        'rule_type': _ruleType,
        'trigger_events': _selectedEvents.toList(),
        'trigger_filter': _triggerFilter,
        'conditions': conditions,
        'actions': _ruleType == 'decision_table' ? [] : _actions,
        'else_actions': _ruleType == 'decision_table' ? [] : _elseActions,
        'approval_required': _approvalRequired,
        'required_approvers': approversList,
      };
      if (widget.rule == null) {
        await dio.post('/rules', data: payload);
      } else {
        final note = _versionNoteCtrl.text.trim();
        if (note.isNotEmpty) payload['version_note'] = note;
        await dio.put('/rules/${widget.rule!['id']}', data: payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorBorder));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Populate all editor fields from an AI-generated rule dict.
  void _applyAIRule(Map<String, dynamic> r) {
    setState(() {
      _nameCtrl.text = r['name'] as String? ?? '';
      _descCtrl.text = r['description'] as String? ?? '';
      _priorityCtrl.text = (r['priority'] ?? 100).toString();
      _status = r['status'] as String? ?? 'draft';
      _ruleType = r['rule_type'] as String? ?? 'condition_tree';
      _isActive = r['is_active'] as bool? ?? true;
      _stopOnMatch = r['stop_on_match'] as bool? ?? false;
      _approvalRequired = r['approval_required'] as bool? ?? false;
      final approvers = (r['required_approvers'] as List?)?.cast<String>() ?? [];
      _approversCtrl.text = approvers.join(', ');
      _selectedEvents = Set<String>.from((r['trigger_events'] as List?) ?? []);
      _triggerFilter = Map<String, String>.from(
          (r['trigger_filter'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {});
      _conditions = Map<String, dynamic>.from(r['conditions'] as Map? ?? {'combinator': 'and', 'rules': []});
      if (_ruleType == 'javascript') {
        _jsCodeCtrl.text = _conditions['code'] as String? ?? '';
      }
      _actions = List<Map<String, dynamic>>.from(
          (r['actions'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ?? []);
      _elseActions = List<Map<String, dynamic>>.from(
          (r['else_actions'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ?? []);
    });
  }

  Future<void> _openAIGenerate() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AIGenerateDialog(),
    );
    if (result != null && mounted) {
      _applyAIRule(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rule populated from AI — review and save')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgSurface,
      child: SizedBox(
        width: 720,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.bgRaised,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(children: [
              const Icon(Icons.rule_outlined, size: 18, color: AppTheme.primaryText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.rule == null
                      ? context.t('rules.editor.new_title')
                      : '${context.t('rules.editor.edit_prefix')} — ${widget.rule!['name']}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textBright),
                ),
              ),
              // AI Generate button
              Tooltip(
                message: context.t('rules.editor.ai_generate_tooltip'),
                child: OutlinedButton.icon(
                  onPressed: _aiGenerating ? null : _openAIGenerate,
                  icon: _aiGenerating
                      ? const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: Text(context.t('rules.editor.ai_generate'),
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.purpleText,
                    side: const BorderSide(color: AppTheme.purpleBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => Navigator.of(context).pop(false),
                child: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
              ),
            ]),
          ),
          // Tabs
          Container(
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.borderSubtle))),
            child: TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: context.t('rules.editor.tab_basics')),
                Tab(text: context.t('rules.editor.tab_triggers')),
                Tab(text: _ruleType == 'decision_table'
                    ? context.t('rules.editor.tab_decision_table')
                    : _ruleType == 'javascript'
                        ? context.t('rules.editor.tab_script')
                        : context.t('rules.editor.tab_conditions')),
                Tab(text: _ruleType == 'decision_table'
                    ? context.t('rules.editor.tab_na')
                    : context.t('rules.editor.tab_actions')),
              ],
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _BasicsTab(
                nameCtrl: _nameCtrl,
                descCtrl: _descCtrl,
                priorityCtrl: _priorityCtrl,
                approversCtrl: _approversCtrl,
                isActive: _isActive,
                stopOnMatch: _stopOnMatch,
                approvalRequired: _approvalRequired,
                status: _status,
                ruleType: _ruleType,
                onActiveChanged: (v) => setState(() => _isActive = v),
                onStopOnMatchChanged: (v) => setState(() => _stopOnMatch = v),
                onApprovalRequiredChanged: (v) => setState(() => _approvalRequired = v),
                onStatusChanged: (v) => setState(() => _status = v),
                onRuleTypeChanged: (v) {
                  setState(() {
                    _ruleType = v;
                    // Reset conditions to appropriate default
                    if (v == 'decision_table') {
                      _conditions = {'input_columns': [], 'output_columns': [], 'rows': []};
                    } else if (v == 'javascript') {
                      _conditions = {'code': _jsCodeCtrl.text};
                    } else {
                      _conditions = {'combinator': 'and', 'rules': []};
                    }
                  });
                },
              ),
              _TriggersTab(
                selectedEvents: _selectedEvents,
                triggerFilter: _triggerFilter,
                filterKeyCtrl: _filterKeyCtrl,
                filterValCtrl: _filterValCtrl,
                onEventsChanged: (s) => setState(() => _selectedEvents = s),
                onFilterChanged: (m) => setState(() => _triggerFilter = m),
              ),
              if (_ruleType == 'decision_table')
                _DecisionTableTab(
                  table: _conditions,
                  onChanged: (t) => setState(() => _conditions = t),
                )
              else if (_ruleType == 'javascript')
                _JSCodeTab(
                  codeCtrl: _jsCodeCtrl,
                  onChanged: (code) => setState(() => _conditions = {'code': code}),
                )
              else
                // Domain-aware condition builder when a pack publishes its
                // data_domains schema (pick domain→field→value from dropdowns);
                // falls back to the manual field/operator/value editor (the
                // raw escape hatch) when no domain schema is available.
                Builder(builder: (_) {
                  final domains = ref.watch(nodeTypeRegistryProvider).maybeWhen(
                        data: (r) => r.packDataDomains,
                        orElse: () => const <Map<String, dynamic>>[],
                      );
                  if (domains.isNotEmpty) {
                    return SchemaConditionBuilder(
                      domains: domains,
                      value: _conditions,
                      onChanged: (c) => setState(() => _conditions = c),
                    );
                  }
                  return _ConditionsTab(
                    conditions: _conditions,
                    onChanged: (c) => setState(() => _conditions = c),
                  );
                }),
              if (_ruleType == 'decision_table')
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.table_chart_outlined, size: 40, color: AppTheme.textMuted),
                    const SizedBox(height: 8),
                    Text(context.t('rules.editor.dt_no_actions'),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(context.t('rules.editor.dt_outputs_in_table'),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ]),
                )
              else
                _ActionsTab(
                  actions: _actions,
                  elseActions: _elseActions,
                  onChanged: (a) => setState(() => _actions = a),
                  onElseChanged: (a) => setState(() => _elseActions = a),
                ),
            ]),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.borderSubtle))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Version note — only when editing an existing rule
              if (widget.rule != null) ...[
                Row(children: [
                  const Icon(Icons.notes_outlined, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _versionNoteCtrl,
                      decoration: InputDecoration(
                        hintText: context.t('rules.editor.change_note_hint'),
                        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        filled: true,
                        fillColor: AppTheme.bgRaised,
                        border: const OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(context.t('common.cancel'))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(context.t('rules.editor.save_rule')),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Tab: Basics ──────────────────────────────────────────────────────────────

class _BasicsTab extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController priorityCtrl;
  final TextEditingController approversCtrl;
  final bool isActive;
  final bool stopOnMatch;
  final bool approvalRequired;
  final String status;
  final String ruleType;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<bool> onStopOnMatchChanged;
  final ValueChanged<bool> onApprovalRequiredChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onRuleTypeChanged;

  const _BasicsTab({
    required this.nameCtrl,
    required this.descCtrl,
    required this.priorityCtrl,
    required this.approversCtrl,
    required this.isActive,
    required this.stopOnMatch,
    required this.approvalRequired,
    required this.status,
    required this.ruleType,
    required this.onActiveChanged,
    required this.onStopOnMatchChanged,
    required this.onApprovalRequiredChanged,
    required this.onStatusChanged,
    required this.onRuleTypeChanged,
  });

  static InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppTheme.bgRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(context.t('rules.editor.basics.rule_details'), style: AppTheme.sectionLabel),
      const SizedBox(height: 10),
      Text(context.t('rules.editor.basics.name'), style: AppTheme.labelStyle),
      const SizedBox(height: 4),
      TextField(controller: nameCtrl, decoration: _dec(context.t('rules.editor.basics.name_hint'))),
      const SizedBox(height: 12),
      Text(context.t('rules.editor.basics.description'), style: AppTheme.labelStyle),
      const SizedBox(height: 4),
      TextField(controller: descCtrl, decoration: _dec(context.t('rules.editor.basics.description_hint')), maxLines: 2),
      const SizedBox(height: 12),
      Text(context.t('rules.editor.basics.priority'), style: AppTheme.labelStyle),
      const SizedBox(height: 2),
      Text(context.t('rules.editor.basics.priority_hint'), style: AppTheme.captionStyle),
      const SizedBox(height: 4),
      SizedBox(
        width: 120,
        child: TextField(
          controller: priorityCtrl,
          keyboardType: TextInputType.number,
          decoration: _dec('100'),
        ),
      ),
      const SizedBox(height: 20),
      Text(context.t('rules.editor.basics.rule_type'), style: AppTheme.sectionLabel),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _TypeOption(
            label: context.t('rules.editor.basics.condition_tree'),
            subtitle: context.t('rules.editor.basics.condition_tree_subtitle'),
            icon: Icons.account_tree_outlined,
            selected: ruleType == 'condition_tree',
            onTap: () => onRuleTypeChanged('condition_tree'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TypeOption(
            label: context.t('rules.editor.basics.decision_table'),
            subtitle: context.t('rules.editor.basics.decision_table_subtitle'),
            icon: Icons.table_chart_outlined,
            selected: ruleType == 'decision_table',
            onTap: () => onRuleTypeChanged('decision_table'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TypeOption(
            label: context.t('rules.editor.basics.javascript'),
            subtitle: context.t('rules.editor.basics.javascript_subtitle'),
            icon: Icons.code_outlined,
            selected: ruleType == 'javascript',
            onTap: () => onRuleTypeChanged('javascript'),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Text(context.t('rules.editor.basics.status'), style: AppTheme.sectionLabel),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _TypeOption(
            label: context.t('rules.editor.basics.draft'),
            subtitle: context.t('rules.editor.basics.draft_subtitle'),
            icon: Icons.edit_note_outlined,
            selected: status == 'draft',
            onTap: () => onStatusChanged('draft'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TypeOption(
            label: context.t('rules.editor.basics.published'),
            subtitle: context.t('rules.editor.basics.published_subtitle'),
            icon: Icons.cloud_done_outlined,
            selected: status == 'published',
            onTap: () => onStatusChanged('published'),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Text(context.t('rules.editor.basics.behaviour'), style: AppTheme.sectionLabel),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('rules.editor.basics.active'), style: AppTheme.labelStyle),
          Text(context.t('rules.editor.basics.active_hint'), style: AppTheme.captionStyle),
        ])),
        Switch(value: isActive, onChanged: onActiveChanged),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('rules.editor.basics.stop_on_match'), style: AppTheme.labelStyle),
          Text(context.t('rules.editor.basics.stop_on_match_hint'), style: AppTheme.captionStyle),
        ])),
        Switch(value: stopOnMatch, onChanged: onStopOnMatchChanged),
      ]),
      const SizedBox(height: 20),
      Text(context.t('rules.editor.basics.approval_workflow'), style: AppTheme.sectionLabel),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('rules.editor.basics.require_approval'), style: AppTheme.labelStyle),
          Text(context.t('rules.editor.basics.require_approval_hint'), style: AppTheme.captionStyle),
        ])),
        Switch(value: approvalRequired, onChanged: onApprovalRequiredChanged),
      ]),
      if (approvalRequired) ...[
        const SizedBox(height: 10),
        Text(context.t('rules.editor.basics.required_approvers'), style: AppTheme.labelStyle),
        const SizedBox(height: 4),
        TextField(
          controller: approversCtrl,
          decoration: _dec('alice@company.com, bob@company.com'),
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(context.t('rules.editor.basics.required_approvers_hint'),
            style: AppTheme.captionStyle),
      ],
    ]);
  }
}

class _TypeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TypeOption({
    required this.label, required this.subtitle, required this.icon,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryBg : AppTheme.bgRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: selected ? AppTheme.primaryText : AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: selected ? AppTheme.primaryText : AppTheme.textSecondary,
              )),
              Text(subtitle, style: TextStyle(
                fontSize: 10,
                color: selected ? AppTheme.primaryText.withValues(alpha: 0.7) : AppTheme.textMuted,
              )),
            ]),
          ),
          if (selected)
            const Icon(Icons.radio_button_checked, size: 14, color: AppTheme.primary)
          else
            const Icon(Icons.radio_button_unchecked, size: 14, color: AppTheme.textMuted),
        ]),
      ),
    );
  }
}

// ─── Tab: Triggers ────────────────────────────────────────────────────────────

class _TriggersTab extends StatelessWidget {
  final Set<String> selectedEvents;
  final Map<String, String> triggerFilter;
  final TextEditingController filterKeyCtrl;
  final TextEditingController filterValCtrl;
  final ValueChanged<Set<String>> onEventsChanged;
  final ValueChanged<Map<String, String>> onFilterChanged;

  const _TriggersTab({
    required this.selectedEvents,
    required this.triggerFilter,
    required this.filterKeyCtrl,
    required this.filterValCtrl,
    required this.onEventsChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(context.t('rules.editor.triggers.when_to_evaluate'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      Text(context.t('rules.editor.triggers.when_to_evaluate_hint'),
          style: AppTheme.captionStyle),
      const SizedBox(height: 12),
      for (final ev in kTriggerEvents)
        _EventToggle(
          label: ev['label'] as String,
          value: ev['value'] as String,
          selected: selectedEvents.contains(ev['value']),
          onChanged: (sel) {
            final next = Set<String>.from(selectedEvents);
            sel ? next.add(ev['value'] as String) : next.remove(ev['value']);
            onEventsChanged(next);
          },
        ),
      const SizedBox(height: 24),
      Text(context.t('rules.editor.triggers.filter'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      Text(
        context.t('rules.editor.triggers.filter_hint'),
        style: AppTheme.captionStyle,
      ),
      const SizedBox(height: 12),
      for (final entry in triggerFilter.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bgRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Row(children: [
                  Text(entry.key,
                      style: const TextStyle(fontSize: 12, color: AppTheme.codeText,
                          fontFamily: 'monospace')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('=', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  Text(entry.value,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                final next = Map<String, String>.from(triggerFilter)..remove(entry.key);
                onFilterChanged(next);
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.remove_circle_outline, size: 16, color: AppTheme.errorText),
              ),
            ),
          ]),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: filterKeyCtrl,
            decoration: InputDecoration(
              hintText: context.t('rules.editor.triggers.filter_key_hint'),
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: AppTheme.bgRaised,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('=', style: TextStyle(color: AppTheme.textMuted)),
        ),
        Expanded(
          child: TextField(
            controller: filterValCtrl,
            decoration: InputDecoration(
              hintText: context.t('rules.editor.triggers.filter_value_hint'),
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: AppTheme.bgRaised,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: () {
            final k = filterKeyCtrl.text.trim();
            final v = filterValCtrl.text.trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              onFilterChanged({...triggerFilter, k: v});
              filterKeyCtrl.clear();
              filterValCtrl.clear();
            }
          },
          icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryText),
          tooltip: context.t('rules.editor.triggers.add_filter'),
        ),
      ]),
    ]);
  }
}

class _EventToggle extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<bool> onChanged;
  const _EventToggle({required this.label, required this.value, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.purpleBg : AppTheme.bgRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppTheme.purpleBorder : AppTheme.borderSubtle),
        ),
        child: Row(children: [
          Icon(selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16, color: selected ? AppTheme.purpleText : AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 13,
                  color: selected ? AppTheme.purpleText : AppTheme.textSecondary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.bgPage,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(value,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted)),
          ),
        ]),
      ),
    );
  }
}

// ─── Tab: Conditions ──────────────────────────────────────────────────────────

class _ConditionsTab extends StatefulWidget {
  final Map<String, dynamic> conditions;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const _ConditionsTab({required this.conditions, required this.onChanged});

  @override
  State<_ConditionsTab> createState() => _ConditionsTabState();
}

class _ConditionsTabState extends State<_ConditionsTab> {
  late Map<String, dynamic> _tree;

  @override
  void initState() {
    super.initState();
    _tree = _deepCopy(widget.conditions);
    if (!_tree.containsKey('combinator')) _tree = {'combinator': 'and', 'rules': []};
  }

  static Map<String, dynamic> _deepCopy(Map m) =>
      Map<String, dynamic>.from(m.map((k, v) {
        if (v is Map) return MapEntry(k, _deepCopy(v));
        if (v is List) return MapEntry(k, v.map((e) => e is Map ? _deepCopy(e) : e).toList());
        return MapEntry(k, v);
      }));

  void _notify() {
    widget.onChanged(Map<String, dynamic>.from(_tree));
  }

  @override
  Widget build(BuildContext context) {
    final rules = (_tree['rules'] as List?) ?? [];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Text(context.t('rules.editor.conditions.when'), style: AppTheme.sectionLabel),
        const SizedBox(width: 8),
        _CombinatorPicker(
          value: _tree['combinator'] as String? ?? 'and',
          onChanged: (v) => setState(() {
            _tree['combinator'] = v;
            _notify();
          }),
        ),
        const SizedBox(width: 8),
        Text(context.t('rules.editor.conditions.of_these_met'), style: AppTheme.sectionLabel),
        const Spacer(),
        Text(context.t('rules.editor.conditions.empty_matches'), style: AppTheme.captionStyle),
      ]),
      const SizedBox(height: 12),
      for (int i = 0; i < rules.length; i++)
        _ConditionRow(
          rule: Map<String, dynamic>.from(rules[i] as Map),
          depth: 0,
          onUpdate: (updated) {
            setState(() {
              ((_tree['rules'] as List))[i] = updated;
              _notify();
            });
          },
          onDelete: () {
            setState(() {
              (_tree['rules'] as List).removeAt(i);
              _notify();
            });
          },
        ),
      const SizedBox(height: 8),
      Row(children: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              (_tree['rules'] as List).add({'field': '', 'operator': 'eq', 'value': ''});
              _notify();
            });
          },
          icon: const Icon(Icons.add, size: 14),
          label: Text(context.t('rules.editor.conditions.add_condition'),
              style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primaryText, padding: EdgeInsets.zero),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: () {
            setState(() {
              (_tree['rules'] as List).add({'combinator': 'or', 'rules': []});
              _notify();
            });
          },
          icon: const Icon(Icons.add, size: 14),
          label: Text(context.t('rules.editor.conditions.add_group'),
              style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.purpleText, padding: EdgeInsets.zero),
        ),
      ]),
    ]);
  }
}

class _CombinatorPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _CombinatorPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        isDense: true,
        dropdownColor: AppTheme.bgRaised,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryText),
        items: ['and', 'or', 'not'].map((v) =>
            DropdownMenuItem(value: v, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(v.toUpperCase()),
            ))).toList(),
        onChanged: (v) => onChanged(v!),
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  final Map<String, dynamic> rule;
  final int depth;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onDelete;

  const _ConditionRow({
    required this.rule,
    required this.depth,
    required this.onUpdate,
    required this.onDelete,
  });

  static InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: AppTheme.bgRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    // Nested group
    if (rule.containsKey('combinator')) {
      final subRules = (rule['rules'] as List?) ?? [];
      return Container(
        margin: const EdgeInsets.only(bottom: 6, left: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bgPage,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.purpleBorder.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _CombinatorPicker(
              value: rule['combinator'] as String? ?? 'or',
              onChanged: (v) => onUpdate({...rule, 'combinator': v}),
            ),
            const SizedBox(width: 8),
            Text('group', style: AppTheme.captionStyle),
            const Spacer(),
            InkWell(onTap: onDelete, child: const Icon(Icons.remove_circle_outline, size: 14, color: AppTheme.errorText)),
          ]),
          const SizedBox(height: 6),
          for (int i = 0; i < subRules.length; i++)
            _ConditionRow(
              rule: Map<String, dynamic>.from(subRules[i] as Map),
              depth: depth + 1,
              onUpdate: (u) {
                final next = List.from(subRules)..[i] = u;
                onUpdate({...rule, 'rules': next});
              },
              onDelete: () {
                final next = List.from(subRules)..removeAt(i);
                onUpdate({...rule, 'rules': next});
              },
            ),
          TextButton.icon(
            onPressed: () {
              final next = List.from(subRules)..add({'field': '', 'operator': 'eq', 'value': ''});
              onUpdate({...rule, 'rules': next});
            },
            icon: const Icon(Icons.add, size: 12),
            label: const Text('Add condition', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryText, padding: EdgeInsets.zero),
          ),
        ]),
      );
    }

    // Leaf condition
    final op = rule['operator'] as String? ?? 'eq';
    final noValue = ['is_empty', 'is_not_empty', 'is_true', 'is_false'].contains(op);
    final valueHint = op == 'between'
        ? 'min,max'
        : (op == 'in' || op == 'not_in')
            ? 'a,b,c'
            : op.startsWith('date') || op.endsWith('_n_days')
                ? op.endsWith('_n_days') ? '7' : 'YYYY-MM-DD'
                : 'value';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: TextEditingController(text: rule['field'] as String? ?? ''),
            onChanged: (v) => onUpdate({...rule, 'field': v}),
            decoration: _dec('data.email'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: kOperators.any((o) => o['value'] == op) ? op : 'eq',
            isDense: true,
            dropdownColor: AppTheme.bgRaised,
            style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            decoration: _dec(''),
            onChanged: (v) => onUpdate({...rule, 'operator': v}),
            items: kOperators.map((o) => DropdownMenuItem(
              value: o['value'],
              child: Text(o['label'] as String, style: const TextStyle(fontSize: 11)),
            )).toList(),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: noValue
              ? const SizedBox()
              : TextField(
                  controller: TextEditingController(text: rule['value'] as String? ?? ''),
                  onChanged: (v) => onUpdate({...rule, 'value': v}),
                  decoration: _dec(valueHint),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onDelete,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.remove_circle_outline, size: 14, color: AppTheme.errorText),
          ),
        ),
      ]),
    );
  }
}

// ─── Tab: JavaScript Code Editor (Gap 11) ─────────────────────────────────────

class _JSCodeTab extends StatefulWidget {
  final TextEditingController codeCtrl;
  final ValueChanged<String> onChanged;
  const _JSCodeTab({required this.codeCtrl, required this.onChanged});

  @override
  State<_JSCodeTab> createState() => _JSCodeTabState();
}

class _JSCodeTabState extends State<_JSCodeTab> {
  String? _syntaxError;
  bool _validating = false;

  Future<void> _validate(WidgetRef ref) async {
    final code = widget.codeCtrl.text.trim();
    if (code.isEmpty) { setState(() => _syntaxError = null); return; }
    setState(() { _validating = true; _syntaxError = null; });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/rules/validate-js', data: {'code': code});
      final valid = resp.data['valid'] as bool? ?? false;
      setState(() {
        _syntaxError = valid ? null : (resp.data['error'] as String? ?? 'Syntax error');
        _validating = false;
      });
    } catch (_) {
      setState(() { _validating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('rules.editor.js_code.title'), style: AppTheme.sectionLabel),
            const SizedBox(height: 4),
            Text(
              context.t('rules.editor.js_code.help'),
              style: AppTheme.captionStyle,
            ),
          ])),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _validating ? null : () => _validate(ref),
            icon: _validating
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 14),
            label: Text(_validating
                  ? context.t('rules.editor.js_code.checking')
                  : context.t('rules.editor.js_code.check_syntax'),
                style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.successText,
              side: const BorderSide(color: AppTheme.successBorder),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Code editor area
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _syntaxError != null ? AppTheme.errorBorder : AppTheme.borderSubtle,
              width: _syntaxError != null ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: widget.codeCtrl,
            onChanged: (v) {
              widget.onChanged(v);
              setState(() => _syntaxError = null);
            },
            maxLines: 20,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Color(0xFFE6EDF3),
              height: 1.5,
            ),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(14),
              border: InputBorder.none,
              hintText: '// Example: match high-value leads\nvar amount = event.data && event.data.amount;\namount > 1000 && event.customer_tier === "premium";',
              hintStyle: TextStyle(
                fontSize: 11, fontFamily: 'monospace',
                color: Color(0xFF484F58), height: 1.6,
              ),
            ),
          ),
        ),
        if (_syntaxError != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.errorBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.errorBorder),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 14, color: AppTheme.errorText),
              const SizedBox(width: 8),
              Expanded(child: Text(_syntaxError!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.errorText))),
            ]),
          ),
        ] else if (!_validating && widget.codeCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.successBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.successBorder),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, size: 14, color: AppTheme.successText),
              const SizedBox(width: 8),
              Text(context.t('rules.editor.js_code.syntax_ok'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.successText)),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        // Reference card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('rules.editor.js_code.quick_reference'), style: AppTheme.sectionLabel),
            const SizedBox(height: 8),
            for (final example in [
              ['event', 'Full event data object'],
              ['event.data.field', 'Access nested fields'],
              ['true / false', 'Simple boolean match'],
              ['({ matched: true, data: { tier: "gold" } })', 'Match + set output fields'],
              ['({ matched: false })', 'Explicit no-match'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 260,
                    child: Text(example[0],
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                            color: AppTheme.codeText)),
                  ),
                  Expanded(child: Text(example[1],
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
                ]),
              ),
          ]),
        ),
      ]);
    });
  }
}

// ─── Tab: Actions (with Else section) ─────────────────────────────────────────

class _ActionsTab extends StatefulWidget {
  final List<Map<String, dynamic>> actions;
  final List<Map<String, dynamic>> elseActions;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final ValueChanged<List<Map<String, dynamic>>> onElseChanged;
  const _ActionsTab({
    required this.actions,
    required this.elseActions,
    required this.onChanged,
    required this.onElseChanged,
  });

  @override
  State<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends State<_ActionsTab> {
  late List<Map<String, dynamic>> _actions;
  late List<Map<String, dynamic>> _elseActions;
  bool _elseExpanded = false;

  @override
  void initState() {
    super.initState();
    _actions = List<Map<String, dynamic>>.from(
        widget.actions.map((a) => Map<String, dynamic>.from(a)));
    _elseActions = List<Map<String, dynamic>>.from(
        widget.elseActions.map((a) => Map<String, dynamic>.from(a)));
    _elseExpanded = _elseActions.isNotEmpty;
  }

  void _addThen() {
    setState(() => _actions.add({'type': 'trigger_workflow'}));
    widget.onChanged(List.from(_actions));
  }

  void _removeThen(int i) {
    setState(() => _actions.removeAt(i));
    widget.onChanged(List.from(_actions));
  }

  void _updateThen(int i, Map<String, dynamic> updated) {
    setState(() => _actions[i] = updated);
    widget.onChanged(List.from(_actions));
  }

  void _addElse() {
    setState(() => _elseActions.add({'type': 'send_email'}));
    widget.onElseChanged(List.from(_elseActions));
  }

  void _removeElse(int i) {
    setState(() => _elseActions.removeAt(i));
    widget.onElseChanged(List.from(_elseActions));
  }

  void _updateElse(int i, Map<String, dynamic> updated) {
    setState(() => _elseActions[i] = updated);
    widget.onElseChanged(List.from(_elseActions));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      // ── THEN section ────────────────────────────────────────────────────
      Text(context.t('rules.editor.actions.if_match_then'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      Text(context.t('rules.editor.actions.then_hint'),
          style: AppTheme.captionStyle),
      const SizedBox(height: 16),
      for (int i = 0; i < _actions.length; i++)
        _ActionCard(
          index: i,
          action: _actions[i],
          onUpdate: (u) => _updateThen(i, u),
          onDelete: () => _removeThen(i),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _addThen,
        icon: const Icon(Icons.add, size: 14),
        label: Text(context.t('rules.editor.actions.add_action'),
            style: const TextStyle(fontSize: 13)),
        style: TextButton.styleFrom(foregroundColor: AppTheme.primaryText),
      ),
      const SizedBox(height: 24),
      // ── ELSE section ────────────────────────────────────────────────────
      InkWell(
        onTap: () => setState(() => _elseExpanded = !_elseExpanded),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _elseExpanded ? AppTheme.warningBg : AppTheme.bgRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _elseExpanded ? AppTheme.warningBorder : AppTheme.borderSubtle,
            ),
          ),
          child: Row(children: [
            Icon(
              _elseExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: _elseExpanded ? AppTheme.warningText : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  context.t('rules.editor.actions.otherwise_else'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _elseExpanded ? AppTheme.warningText : AppTheme.textMuted,
                  ),
                ),
                Text(
                  context.t('rules.editor.actions.else_hint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _elseExpanded ? AppTheme.warningText : AppTheme.textMuted,
                  ),
                ),
              ]),
            ),
            if (_elseActions.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: AppTheme.pill(bg: AppTheme.warningBg, border: AppTheme.warningBorder),
                child: Text('${_elseActions.length} ${context.t('rules.editor.actions.action_count_suffix')}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.warningText)),
              ),
          ]),
        ),
      ),
      if (_elseExpanded) ...[
        const SizedBox(height: 12),
        for (int i = 0; i < _elseActions.length; i++)
          _ActionCard(
            index: i,
            action: _elseActions[i],
            onUpdate: (u) => _updateElse(i, u),
            onDelete: () => _removeElse(i),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _addElse,
          icon: const Icon(Icons.add, size: 14),
          label: Text(context.t('rules.editor.actions.add_else_action'),
              style: const TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.warningText),
        ),
      ],
    ]);
  }
}

class _ActionCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> action;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onDelete;
  const _ActionCard({
    required this.index,
    required this.action,
    required this.onUpdate,
    required this.onDelete,
  });

  static InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: AppTheme.bgPage,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: AppTheme.primary)),
      );

  Widget _field(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.labelStyle),
          const SizedBox(height: 3),
          child,
          const SizedBox(height: 10),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final type = action['type'] as String? ?? 'trigger_workflow';
    final meta = kActionTypes.firstWhere(
        (a) => a['value'] == type, orElse: () => kActionTypes.first);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppTheme.primaryBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(meta['icon'] as IconData, size: 14, color: AppTheme.primaryText),
          ),
          const SizedBox(width: 8),
          Text('Step ${index + 1}', style: AppTheme.captionStyle),
          const Spacer(),
          InkWell(onTap: onDelete,
              child: const Icon(Icons.remove_circle_outline, size: 16, color: AppTheme.errorText)),
        ]),
        const SizedBox(height: 10),
        // Type selector
        _field('Action type', DropdownButtonFormField<String>(
          initialValue: type,
          isDense: true,
          dropdownColor: AppTheme.bgRaised,
          decoration: _dec(''),
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          onChanged: (v) => onUpdate({'type': v}),
          items: kActionTypes.map((a) => DropdownMenuItem<String>(
            value: a['value'] as String,
            child: Row(children: [
              Icon(a['icon'] as IconData, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(a['label'] as String, style: const TextStyle(fontSize: 13)),
            ]),
          )).toList(),
        )),
        // Type-specific fields
        ..._buildFields(type, action),
      ]),
    );
  }

  List<Widget> _buildFields(String type, Map<String, dynamic> a) {
    switch (type) {
      case 'trigger_workflow':
        return [
          _field('Workflow ID', TextField(
            controller: TextEditingController(text: a['workflow_id'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'workflow_id': v}),
            decoration: _dec('UUID of the workflow to trigger'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
          )),
        ];
      case 'send_email':
        return [
          _field('To', TextField(
            controller: TextEditingController(text: a['to'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'to': v}),
            decoration: _dec('{{data.email}}'),
          )),
          _field('Subject', TextField(
            controller: TextEditingController(text: a['subject'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'subject': v}),
            decoration: _dec('Your form was submitted'),
          )),
          _field('Body', TextField(
            controller: TextEditingController(text: a['body'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'body': v}),
            decoration: _dec('Hi {{data.name}}, thanks for reaching out...'),
            maxLines: 3,
          )),
        ];
      case 'send_webhook':
        return [
          _field('URL', TextField(
            controller: TextEditingController(text: a['url'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'url': v}),
            decoration: _dec('https://api.example.com/webhook'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
          )),
          _field('Method', TextField(
            controller: TextEditingController(text: a['method'] as String? ?? 'POST'),
            onChanged: (v) => onUpdate({...a, 'method': v}),
            decoration: _dec('POST'),
          )),
        ];
      case 'set_field':
        return [
          _field('Field path', TextField(
            controller: TextEditingController(text: a['field'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'field': v}),
            decoration: _dec('data.category'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
          )),
          _field('Value', TextField(
            controller: TextEditingController(text: a['value'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'value': v}),
            decoration: _dec('vip  or  {{data.country}}-customer  or  {{price * 0.9}}'),
          )),
        ];
      case 'add_tag':
        return [
          _field('Tag', TextField(
            controller: TextEditingController(text: a['tag'] as String? ?? ''),
            onChanged: (v) => onUpdate({...a, 'tag': v}),
            decoration: _dec('high-value  or  {{data.country}}-lead'),
          )),
        ];
      case 'stop_processing':
        return [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warningBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.warningBorder),
            ),
            child: const Text(
              'No configuration needed. Once this action executes, no further rules will be evaluated.',
              style: TextStyle(fontSize: 11, color: AppTheme.warningText),
            ),
          ),
        ];
      default:
        return [];
    }
  }
}

// ─── Tab: Decision Table ──────────────────────────────────────────────────────

class _DecisionTableTab extends StatefulWidget {
  final Map<String, dynamic> table;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const _DecisionTableTab({required this.table, required this.onChanged});

  @override
  State<_DecisionTableTab> createState() => _DecisionTableTabState();
}

class _DecisionTableTabState extends State<_DecisionTableTab> {
  late List<Map<String, dynamic>> _inputCols;
  late List<Map<String, dynamic>> _outputCols;
  late List<Map<String, dynamic>> _rows;
  late String _hitPolicy;  // Gap 14: first | collect_all | any_match | unique

  // Hit policies sourced from lib/constants.dart (kHitPolicies).

  @override
  void initState() {
    super.initState();
    _inputCols = List<Map<String, dynamic>>.from(
        (widget.table['input_columns'] as List?)?.map((c) => Map<String, dynamic>.from(c as Map)) ?? []);
    _outputCols = List<Map<String, dynamic>>.from(
        (widget.table['output_columns'] as List?)?.map((c) => Map<String, dynamic>.from(c as Map)) ?? []);
    _rows = List<Map<String, dynamic>>.from(
        (widget.table['rows'] as List?)?.map((r) => Map<String, dynamic>.from(r as Map)) ?? []);
    _hitPolicy = widget.table['hit_policy'] as String? ?? 'first';
  }

  void _notify() {
    widget.onChanged({
      'input_columns': _inputCols,
      'output_columns': _outputCols,
      'rows': _rows,
      'hit_policy': _hitPolicy,
    });
  }

  void _addInputCol() {
    setState(() {
      _inputCols.add({'field': '', 'label': ''});
      // Add empty condition slot to every row
      for (final row in _rows) {
        final conds = List<Map<String, dynamic>>.from(
            (row['conditions'] as List?)?.map((c) => Map<String, dynamic>.from(c as Map)) ?? []);
        conds.add({'operator': 'eq', 'value': ''});
        row['conditions'] = conds;
      }
    });
    _notify();
  }

  void _addOutputCol() {
    setState(() {
      _outputCols.add({'field': '', 'label': ''});
      for (final row in _rows) {
        final outs = List<Map<String, dynamic>>.from(
            (row['outputs'] as List?)?.map((o) => Map<String, dynamic>.from(o as Map)) ?? []);
        outs.add({'value': ''});
        row['outputs'] = outs;
      }
    });
    _notify();
  }

  void _addRow() {
    setState(() {
      _rows.add({
        'id': 'r${_rows.length + 1}',
        'conditions': List.generate(_inputCols.length, (_) => {'operator': 'eq', 'value': ''}),
        'outputs': List.generate(_outputCols.length, (_) => {'value': ''}),
        'annotation': '',
      });
    });
    _notify();
  }

  void _removeRow(int i) {
    setState(() => _rows.removeAt(i));
    _notify();
  }

  static InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: AppTheme.bgPage,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      // ── Gap 14: Hit Policy ───────────────────────────────────────────────
      Row(children: [
        Text(context.t('rules.editor.decision_table.hit_policy'), style: AppTheme.sectionLabel),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppTheme.bgRaised,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: DropdownButton<String>(
            value: kHitPolicies.any((p) => p['value'] == _hitPolicy) ? _hitPolicy : 'first',
            underline: const SizedBox(),
            isDense: true,
            dropdownColor: AppTheme.bgRaised,
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            items: kHitPolicies.map((p) => DropdownMenuItem(
              value: p['value'],
              child: Tooltip(
                message: p['desc'] as String,
                child: Text(p['label'] as String, style: const TextStyle(fontSize: 12)),
              ),
            )).toList(),
            onChanged: (v) => setState(() { _hitPolicy = v!; _notify(); }),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          kHitPolicies.firstWhere((p) => p['value'] == _hitPolicy,
              orElse: () => kHitPolicies.first)['desc'] as String,
          style: AppTheme.captionStyle,
        ),
      ]),
      const SizedBox(height: 16),
      // ── Column configuration ─────────────────────────────────────────────
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(context.t('rules.editor.decision_table.input_columns'), style: AppTheme.sectionLabel),
              const Spacer(),
              TextButton.icon(
                onPressed: _addInputCol,
                icon: const Icon(Icons.add, size: 12),
                label: Text(context.t('rules.editor.decision_table.add'),
                    style: const TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primaryText, padding: EdgeInsets.zero),
              ),
            ]),
            const SizedBox(height: 6),
            for (int i = 0; i < _inputCols.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _inputCols[i]['field'] as String? ?? ''),
                      onChanged: (v) { _inputCols[i]['field'] = v; _notify(); },
                      decoration: _dec('data.field'),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.codeText),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _inputCols[i]['label'] as String? ?? ''),
                      onChanged: (v) { _inputCols[i]['label'] = v; _notify(); },
                      decoration: _dec(context.t('rules.editor.decision_table.label')),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                    ),
                  ),
                  InkWell(
                    onTap: () { setState(() => _inputCols.removeAt(i)); _notify(); },
                    child: const Padding(padding: EdgeInsets.all(4),
                      child: Icon(Icons.remove_circle_outline, size: 14, color: AppTheme.errorText)),
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(context.t('rules.editor.decision_table.output_columns'), style: AppTheme.sectionLabel),
              const Spacer(),
              TextButton.icon(
                onPressed: _addOutputCol,
                icon: const Icon(Icons.add, size: 12),
                label: Text(context.t('rules.editor.decision_table.add'),
                    style: const TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: AppTheme.successText, padding: EdgeInsets.zero),
              ),
            ]),
            const SizedBox(height: 6),
            for (int i = 0; i < _outputCols.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _outputCols[i]['field'] as String? ?? ''),
                      onChanged: (v) { _outputCols[i]['field'] = v; _notify(); },
                      decoration: _dec('data.output'),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.codeText),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _outputCols[i]['label'] as String? ?? ''),
                      onChanged: (v) { _outputCols[i]['label'] = v; _notify(); },
                      decoration: _dec(context.t('rules.editor.decision_table.label')),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                    ),
                  ),
                  InkWell(
                    onTap: () { setState(() => _outputCols.removeAt(i)); _notify(); },
                    child: const Padding(padding: EdgeInsets.all(4),
                      child: Icon(Icons.remove_circle_outline, size: 14, color: AppTheme.errorText)),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 20),

      // ── Rows grid ────────────────────────────────────────────────────────
      Row(children: [
        Text(context.t('rules.editor.decision_table.rows'), style: AppTheme.sectionLabel),
        const Spacer(),
        TextButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add, size: 12),
          label: Text(context.t('rules.editor.decision_table.add_row'),
              style: const TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primaryText, padding: EdgeInsets.zero),
        ),
      ]),
      const SizedBox(height: 6),
      if (_inputCols.isEmpty && _outputCols.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgRaised,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Text(
            context.t('rules.editor.decision_table.empty_help'),
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        )
      else ...[
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.bgRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(children: [
            const SizedBox(width: 28),
            for (final c in _inputCols) ...[
              Expanded(child: Text(
                c['label'] as String? ?? c['field'] as String? ?? context.t('rules.editor.decision_table.input'),
                style: const TextStyle(fontSize: 10, color: AppTheme.infoText, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              )),
            ],
            for (final c in _outputCols) ...[
              Expanded(child: Text(
                c['label'] as String? ?? c['field'] as String? ?? context.t('rules.editor.decision_table.output'),
                style: const TextStyle(fontSize: 10, color: AppTheme.successText, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              )),
            ],
            Expanded(child: Text(context.t('rules.editor.decision_table.annotation'),
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted))),
            const SizedBox(width: 28),
          ]),
        ),
        // Data rows
        for (int ri = 0; ri < _rows.length; ri++)
          _DecisionRow(
            rowIndex: ri,
            row: _rows[ri],
            inputCount: _inputCols.length,
            outputCount: _outputCols.length,
            onChanged: (updated) {
              setState(() => _rows[ri] = updated);
              _notify();
            },
            onDelete: () => _removeRow(ri),
          ),
      ],
    ]);
  }
}

class _DecisionRow extends StatelessWidget {
  final int rowIndex;
  final Map<String, dynamic> row;
  final int inputCount;
  final int outputCount;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  const _DecisionRow({
    required this.rowIndex, required this.row, required this.inputCount,
    required this.outputCount, required this.onChanged, required this.onDelete,
  });

  static const _ops = ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'contains', 'between', 'ANY'];

  static InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        filled: true,
        fillColor: AppTheme.bgPage,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.borderSubtle)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppTheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final conditions = List<Map<String, dynamic>>.from(
        (row['conditions'] as List?)?.map((c) => Map<String, dynamic>.from(c as Map)) ?? []);
    final outputs = List<Map<String, dynamic>>.from(
        (row['outputs'] as List?)?.map((o) => Map<String, dynamic>.from(o as Map)) ?? []);

    return Container(
      decoration: BoxDecoration(
        color: rowIndex.isOdd ? AppTheme.bgPage : AppTheme.bgSurface,
        border: const Border(
          left: BorderSide(color: AppTheme.borderSubtle),
          right: BorderSide(color: AppTheme.borderSubtle),
          bottom: BorderSide(color: AppTheme.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        // Row number
        SizedBox(
          width: 28,
          child: Text('${rowIndex + 1}',
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              textAlign: TextAlign.center),
        ),
        // Input condition cells
        for (int ci = 0; ci < inputCount; ci++) ...[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(children: [
                // Operator dropdown
                DropdownButtonFormField<String>(
                  initialValue: ci < conditions.length
                      ? (conditions[ci]['operator'] as String? ?? 'eq')
                      : 'eq',
                  isDense: true,
                  dropdownColor: AppTheme.bgRaised,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
                  decoration: _dec('op'),
                  onChanged: (v) {
                    while (conditions.length <= ci) {
                      conditions.add({'operator': 'eq', 'value': ''});
                    }
                    conditions[ci] = {...conditions[ci], 'operator': v};
                    onChanged({...row, 'conditions': conditions});
                  },
                  items: _ops.map((op) => DropdownMenuItem(
                    value: op,
                    child: Text(op, style: const TextStyle(fontSize: 10)),
                  )).toList(),
                ),
                const SizedBox(height: 3),
                // Value input (hidden for ANY)
                if (ci < conditions.length && conditions[ci]['operator'] != 'ANY')
                  TextField(
                    controller: TextEditingController(
                        text: ci < conditions.length
                            ? conditions[ci]['value'] as String? ?? ''
                            : ''),
                    onChanged: (v) {
                      while (conditions.length <= ci) {
                        conditions.add({'operator': 'eq', 'value': ''});
                      }
                      conditions[ci] = {...conditions[ci], 'value': v};
                      onChanged({...row, 'conditions': conditions});
                    },
                    decoration: _dec('value'),
                    style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
                  )
                else
                  Container(
                    height: 28,
                    alignment: Alignment.center,
                    child: const Text('(any)', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ),
              ]),
            ),
          ),
        ],
        // Output value cells
        for (int oi = 0; oi < outputCount; oi++) ...[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextField(
                controller: TextEditingController(
                    text: oi < outputs.length ? outputs[oi]['value'] as String? ?? '' : ''),
                onChanged: (v) {
                  while (outputs.length <= oi) {
                    outputs.add({'value': ''});
                  }
                  outputs[oi] = {'value': v};
                  onChanged({...row, 'outputs': outputs});
                },
                decoration: _dec('output value'),
                style: const TextStyle(fontSize: 10, color: AppTheme.successText),
              ),
            ),
          ),
        ],
        // Annotation
        Expanded(
          child: TextField(
            controller: TextEditingController(text: row['annotation'] as String? ?? ''),
            onChanged: (v) => onChanged({...row, 'annotation': v}),
            decoration: _dec('note'),
            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
          ),
        ),
        // Delete
        InkWell(
          onTap: onDelete,
          child: const Padding(padding: EdgeInsets.all(4),
            child: Icon(Icons.remove_circle_outline, size: 14, color: AppTheme.errorText)),
        ),
      ]),
    );
  }
}

// ─── Version History bottom sheet ─────────────────────────────────────────────

class _VersionHistorySheet extends ConsumerStatefulWidget {
  final String ruleId;
  final String ruleName;
  final VoidCallback onRestored;
  const _VersionHistorySheet({required this.ruleId, required this.ruleName, required this.onRestored});

  @override
  ConsumerState<_VersionHistorySheet> createState() => _VersionHistorySheetState();
}

class _VersionHistorySheetState extends ConsumerState<_VersionHistorySheet> {
  List<Map<String, dynamic>> _versions = [];
  bool _loading = true;
  String? _restoring;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/rules/${widget.ruleId}/versions');
      setState(() {
        _versions = List<Map<String, dynamic>>.from(resp.data as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _restore(int versionNum) async {
    setState(() => _restoring = versionNum.toString());
    final tRestored = '${context.t('rules.version_history.restored_to')} $versionNum';
    final tErrorPrefix = context.t('rules.version_history.error_prefix');
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/rules/${widget.ruleId}/versions/$versionNum/restore');
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRestored();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tRestored)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tErrorPrefix: $e'), backgroundColor: AppTheme.errorBorder),
        );
        setState(() => _restoring = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, controller) => Column(children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.history, size: 16, color: AppTheme.primaryText),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${context.t('rules.version_history.title')} — ${widget.ruleName}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textBright)),
            ),
            IconButton(onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted)),
          ]),
        ),
        const Divider(color: AppTheme.borderSubtle, height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _versions.isEmpty
                  ? Center(
                      child: Text(context.t('rules.version_history.empty'),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      itemCount: _versions.length,
                      separatorBuilder: (_, __) => const Divider(color: AppTheme.borderSubtle, height: 16),
                      itemBuilder: (_, i) {
                        final v = _versions[i];
                        final vNum = v['version_num'] as int? ?? 0;
                        final createdAt = v['created_at'] as String? ?? '';
                        final isRestoring = _restoring == vNum.toString();
                        return Row(children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text('v$vNum',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryText)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(v['name'] as String? ?? '',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                                      color: AppTheme.textBright)),
                              Text(
                                '${context.t('rules.version_history.saved_prefix')} ${_formatDate(createdAt)} · '
                                '${(v['actions'] as List?)?.length ?? 0} ${context.t('rules.version_history.actions_suffix')}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                              if ((v['note'] as String?)?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 2),
                                Row(children: [
                                  const Icon(Icons.notes_outlined, size: 11, color: AppTheme.infoText),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(v['note'] as String,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.infoText),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ]),
                              ],
                            ]),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: isRestoring ? null : () => _restore(vNum),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              side: const BorderSide(color: AppTheme.primary),
                              foregroundColor: AppTheme.primaryText,
                            ),
                            child: isRestoring
                                ? const SizedBox(width: 12, height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(context.t('rules.version_history.restore'),
                                    style: const TextStyle(fontSize: 12)),
                          ),
                        ]);
                      },
                    ),
        ),
      ]),
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ─── Audit Log bottom sheet ───────────────────────────────────────────────────

class _AuditLogSheet extends ConsumerStatefulWidget {
  final String ruleId;
  final String ruleName;
  const _AuditLogSheet({required this.ruleId, required this.ruleName});

  @override
  ConsumerState<_AuditLogSheet> createState() => _AuditLogSheetState();
}

class _AuditLogSheetState extends ConsumerState<_AuditLogSheet> {
  List<Map<String, dynamic>> _entries = [];
  Map<String, dynamic>? _analytics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/rules/${widget.ruleId}/audit', queryParameters: {'limit': 20}),
        dio.get('/rules/${widget.ruleId}/analytics'),
      ]);
      setState(() {
        _entries = List<Map<String, dynamic>>.from(results[0].data as List);
        _analytics = results[1].data as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (_, controller) => Column(children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.bar_chart_outlined, size: 16, color: AppTheme.primaryText),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${context.t('rules.audit_log.title')} — ${widget.ruleName}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppTheme.textBright)),
            ),
            IconButton(onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted)),
          ]),
        ),
        const Divider(color: AppTheme.borderSubtle, height: 1),
        // Analytics summary strip
        if (!_loading && _analytics != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(children: [
              _StatChip(
                label: context.t('rules.audit_log.total'),
                value: '${_analytics!['total_evaluations'] ?? 0}',
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: context.t('rules.audit_log.match_rate'),
                value: '${(_analytics!['match_rate_pct'] as num?)?.toStringAsFixed(1) ?? '0.0'}%',
                color: AppTheme.successText,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: context.t('rules.audit_log.avg_latency'),
                value: _analytics!['avg_elapsed_ms'] != null
                    ? '${(_analytics!['avg_elapsed_ms'] as num).toStringAsFixed(1)}ms'
                    : '—',
                color: AppTheme.infoText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('rules.audit_log.top_events'), style: AppTheme.captionStyle),
                  const SizedBox(height: 2),
                  Text(
                    (_analytics!['top_event_types'] as Map<String, dynamic>?)
                            ?.entries
                            .take(3)
                            .map((e) => '${e.key}:${e.value}')
                            .join(', ') ??
                        '—',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Text(context.t('rules.audit_log.empty'),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _AuditEntry(entry: _entries[i]),
                    ),
        ),
      ]),
    );
  }
}

class _AuditEntry extends StatefulWidget {
  final Map<String, dynamic> entry;
  const _AuditEntry({required this.entry});

  @override
  State<_AuditEntry> createState() => _AuditEntryState();
}

class _AuditEntryState extends State<_AuditEntry> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final matched = widget.entry['matched'] as bool? ?? false;
    final eventType = widget.entry['event_type'] as String? ?? '';
    final elapsedMs = widget.entry['elapsed_ms'] as int?;
    final createdAt = widget.entry['created_at'] as String? ?? '';
    final actionsExecuted = (widget.entry['actions_executed'] as List?) ?? [];
    final correlationId = widget.entry['correlation_id'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: matched ? AppTheme.successBorder : AppTheme.borderSubtle,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: AppTheme.pill(
                  bg: matched ? AppTheme.successBg : AppTheme.bgPage,
                  border: matched ? AppTheme.successBorder : AppTheme.borderSubtle,
                ),
                child: Text(
                  matched ? '✓ matched' : '✗ no match',
                  style: TextStyle(
                    fontSize: 10,
                    color: matched ? AppTheme.successText : AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: AppTheme.pill(bg: AppTheme.purpleBg, border: AppTheme.purpleBorder),
                child: Text(eventType,
                    style: const TextStyle(fontSize: 10, color: AppTheme.purpleText,
                        fontFamily: 'monospace')),
              ),
              const Spacer(),
              if (elapsedMs != null)
                Text('${elapsedMs}ms',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              const SizedBox(width: 8),
              Text(_formatDate(createdAt),
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              const SizedBox(width: 4),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14, color: AppTheme.textMuted),
            ]),
            if (_expanded) ...[
              if (correlationId != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.link, size: 11, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Text('corr: $correlationId',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted,
                          fontFamily: 'monospace')),
                ]),
              ],
            ],
            if (_expanded && actionsExecuted.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(color: AppTheme.borderSubtle, height: 1),
              const SizedBox(height: 8),
              for (final a in actionsExecuted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.arrow_right, size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${(a as Map)['type'] ?? '?'}'
                      '${a['status'] != null ? ' [${a['status']}]' : ''}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                          fontFamily: 'monospace'),
                    ),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ─── Analytics helpers ────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTheme.captionStyle),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// ─── Analytics bottom sheet ───────────────────────────────────────────────────

class _AnalyticsSheet extends ConsumerStatefulWidget {
  final String ruleId;
  final String ruleName;
  const _AnalyticsSheet({required this.ruleId, required this.ruleName});

  @override
  ConsumerState<_AnalyticsSheet> createState() => _AnalyticsSheetState();
}

class _AnalyticsSheetState extends ConsumerState<_AnalyticsSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/rules/${widget.ruleId}/analytics');
      setState(() { _data = resp.data as Map<String, dynamic>?; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (_, controller) => Column(children: [
        Center(child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.analytics_outlined, size: 16, color: AppTheme.primaryText),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${context.t('rules.analytics.title')} — ${widget.ruleName}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textBright)),
            ),
            IconButton(onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted)),
          ]),
        ),
        const Divider(color: AppTheme.borderSubtle, height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _data == null
                  ? Center(child: Text(context.t('rules.analytics.no_data_yet'),
                      style: const TextStyle(color: AppTheme.textMuted)))
                  : ListView(controller: controller, padding: const EdgeInsets.all(20), children: [
                      // Big stat cards
                      Row(children: [
                        _BigStatCard(label: context.t('rules.analytics.total_evaluations'),
                            value: '${_data!['total_evaluations'] ?? 0}',
                            icon: Icons.bolt_outlined, color: AppTheme.primaryText),
                        const SizedBox(width: 10),
                        _BigStatCard(label: context.t('rules.analytics.match_rate'),
                            value: '${(_data!['match_rate_pct'] as num?)?.toStringAsFixed(1) ?? '0.0'}%',
                            icon: Icons.check_circle_outline, color: AppTheme.successText),
                        const SizedBox(width: 10),
                        _BigStatCard(label: context.t('rules.analytics.no_match'),
                            value: '${_data!['no_match_count'] ?? 0}',
                            icon: Icons.cancel_outlined, color: AppTheme.textMuted),
                      ]),
                      const SizedBox(height: 16),
                      Text(context.t('rules.analytics.latency'), style: AppTheme.sectionLabel),
                      const SizedBox(height: 10),
                      Row(children: [
                        _BigStatCard(label: context.t('rules.analytics.avg'),
                            value: _data!['avg_elapsed_ms'] != null
                                ? '${(_data!['avg_elapsed_ms'] as num).toStringAsFixed(1)}ms'
                                : '—',
                            icon: Icons.speed_outlined, color: AppTheme.infoText),
                        const SizedBox(width: 10),
                        _BigStatCard(label: context.t('rules.analytics.min'),
                            value: _data!['min_elapsed_ms'] != null
                                ? '${_data!['min_elapsed_ms']}ms'
                                : '—',
                            icon: Icons.arrow_downward_outlined, color: AppTheme.successText),
                        const SizedBox(width: 10),
                        _BigStatCard(label: context.t('rules.analytics.max'),
                            value: _data!['max_elapsed_ms'] != null
                                ? '${_data!['max_elapsed_ms']}ms'
                                : '—',
                            icon: Icons.arrow_upward_outlined, color: AppTheme.warningText),
                      ]),
                      const SizedBox(height: 20),
                      Text(context.t('rules.analytics.top_event_types'), style: AppTheme.sectionLabel),
                      const SizedBox(height: 10),
                      ...(_data!['top_event_types'] as Map<String, dynamic>?)
                              ?.entries
                              .toList()
                              .map((e) {
                            final total = (_data!['total_evaluations'] as int?) ?? 1;
                            final pct = total > 0 ? (e.value as int) / total : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(e.key,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                                          fontFamily: 'monospace'))),
                                  Text('${e.value}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                          color: AppTheme.textBright)),
                                ]),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: pct.toDouble(),
                                    backgroundColor: AppTheme.bgRaised,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                    minHeight: 4,
                                  ),
                                ),
                              ]),
                            );
                          })
                              .toList() ??
                          [Text(context.t('rules.analytics.no_data'),
                              style: const TextStyle(color: AppTheme.textMuted))],
                    ]),
        ),
      ]),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _BigStatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.captionStyle),
        ]),
      ),
    );
  }
}

// ─── Test rule dialog (single + batch tabs) ───────────────────────────────────

class _TestRuleDialog extends ConsumerStatefulWidget {
  final String ruleId;
  const _TestRuleDialog({required this.ruleId});

  @override
  ConsumerState<_TestRuleDialog> createState() => _TestRuleDialogState();
}

class _TestRuleDialogState extends ConsumerState<_TestRuleDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Single test
  final _eventTypeCtrl = TextEditingController(text: 'form_submit');
  final _payloadCtrl = TextEditingController(
    text: '{\n  "form_slug": "contact-us",\n  "data": {\n    "email": "user@company.com",\n    "name": "Test User"\n  }\n}',
  );
  Map<String, dynamic>? _singleResult;
  bool _singleTesting = false;
  String? _singleError;

  // Batch test
  final _batchEventTypeCtrl = TextEditingController(text: 'form_submit');
  final _batchRecordsCtrl = TextEditingController(
    text: '[\n  {"form_slug": "contact-us", "data": {"email": "a@company.com", "score": 95}},\n  {"form_slug": "contact-us", "data": {"email": "b@gmail.com", "score": 40}}\n]',
  );
  bool _batchDryRun = true;
  Map<String, dynamic>? _batchResult;
  bool _batchTesting = false;
  String? _batchError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _eventTypeCtrl.dispose();
    _payloadCtrl.dispose();
    _batchEventTypeCtrl.dispose();
    _batchRecordsCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSingle() async {
    setState(() { _singleTesting = true; _singleResult = null; _singleError = null; });
    try {
      final dio = ref.read(dioProvider);
      final payload = jsonDecode(_payloadCtrl.text) as Map<String, dynamic>;
      final resp = await dio.post('/rules/test', data: {
        'event_type': _eventTypeCtrl.text.trim(),
        'event_data': payload,
        'dry_run': true,
      });
      setState(() { _singleResult = resp.data as Map<String, dynamic>; _singleTesting = false; });
    } catch (e) {
      setState(() { _singleError = e.toString(); _singleTesting = false; });
    }
  }

  Future<void> _runBatch() async {
    setState(() { _batchTesting = true; _batchResult = null; _batchError = null; });
    try {
      final dio = ref.read(dioProvider);
      final records = jsonDecode(_batchRecordsCtrl.text) as List;
      final resp = await dio.post('/rules/batch', data: {
        'event_type': _batchEventTypeCtrl.text.trim(),
        'records': records,
        'dry_run': _batchDryRun,
      });
      setState(() { _batchResult = resp.data as Map<String, dynamic>; _batchTesting = false; });
    } catch (e) {
      setState(() { _batchError = e.toString(); _batchTesting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgSurface,
      child: SizedBox(
        width: 620,
        height: MediaQuery.of(context).size.height * 0.80,
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.bgRaised,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(children: [
              const Icon(Icons.science_outlined, size: 16, color: AppTheme.infoText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.t('rules.test.title'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textBright)),
              ),
              InkWell(onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 16, color: AppTheme.textMuted)),
            ]),
          ),
          // Tab bar
          Container(
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.borderSubtle))),
            child: TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: context.t('rules.test.tab_single')),
                Tab(text: context.t('rules.test.tab_batch')),
              ],
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
            ),
          ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              // ── Single test ──────────────────────────────────────────────
              _buildSingleTab(),
              // ── Batch test ───────────────────────────────────────────────
              _buildBatchTab(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildSingleTab() {
    final matched = (_singleResult?['matched_rules'] as List?)?.length ?? 0;
    final total = _singleResult?['total_rules_evaluated'] ?? 0;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(context.t('rules.test.event_type'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      TextField(
        controller: _eventTypeCtrl,
        decoration: const InputDecoration(
          hintText: 'form_submit',
          isDense: true,
          filled: true,
          fillColor: AppTheme.bgRaised,
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppTheme.codeText),
      ),
      const SizedBox(height: 16),
      Text(context.t('rules.test.event_data_json'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      TextField(
        controller: _payloadCtrl,
        maxLines: 8,
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bgRaised,
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _singleTesting ? null : _runSingle,
          icon: _singleTesting
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow, size: 16),
          label: Text(context.t('rules.test.run_test')),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.successBorder),
        ),
      ),
      if (_singleError != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.errorBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.errorBorder)),
          child: Text(_singleError!, style: const TextStyle(fontSize: 12, color: AppTheme.errorText)),
        ),
      ],
      if (_singleResult != null) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text(context.t('rules.test.results'), style: AppTheme.sectionLabel),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: AppTheme.pill(
                bg: matched > 0 ? AppTheme.successBg : AppTheme.bgRaised,
                border: matched > 0 ? AppTheme.successBorder : AppTheme.borderSubtle),
            child: Text('$matched / $total ${context.t('rules.test.rules_matched_suffix')}',
                style: TextStyle(
                    fontSize: 11,
                    color: matched > 0 ? AppTheme.successText : AppTheme.textMuted)),
          ),
        ]),
        const SizedBox(height: 8),
        for (final r in (_singleResult!['matched_rules'] as List?) ?? [])
          _MatchedRuleResult(result: Map<String, dynamic>.from(r as Map)),
      ],
    ]);
  }

  Widget _buildBatchTab() {
    final batchResults = (_batchResult?['results'] as List?) ?? [];
    final total = _batchResult?['total_records'] as int?;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(context.t('rules.test.event_type'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      TextField(
        controller: _batchEventTypeCtrl,
        decoration: const InputDecoration(
          hintText: 'form_submit',
          isDense: true,
          filled: true,
          fillColor: AppTheme.bgRaised,
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppTheme.codeText),
      ),
      const SizedBox(height: 16),
      Text(context.t('rules.test.records_json'), style: AppTheme.sectionLabel),
      const SizedBox(height: 6),
      TextField(
        controller: _batchRecordsCtrl,
        maxLines: 10,
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bgRaised,
          border: OutlineInputBorder(),
          hintText: '[{"field": "value"}, ...]',
          hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Switch(
          value: _batchDryRun,
          onChanged: (v) => setState(() => _batchDryRun = v),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_batchDryRun
                  ? context.t('rules.test.dry_run_label')
                  : context.t('rules.test.live_run_label'),
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: _batchDryRun ? AppTheme.textSecondary : AppTheme.warningText,
                )),
            Text(_batchDryRun
                ? context.t('rules.test.dry_run_hint')
                : context.t('rules.test.live_run_hint'),
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _batchTesting ? null : _runBatch,
          icon: _batchTesting
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.playlist_play, size: 16),
          label: Text(_batchDryRun
              ? context.t('rules.test.run_batch_dry')
              : context.t('rules.test.run_batch_live')),
          style: FilledButton.styleFrom(
            backgroundColor: _batchDryRun ? AppTheme.primary : AppTheme.warningBorder,
          ),
        ),
      ),
      if (_batchError != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.errorBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.errorBorder)),
          child: Text(_batchError!, style: const TextStyle(fontSize: 12, color: AppTheme.errorText)),
        ),
      ],
      if (_batchResult != null) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text(context.t('rules.test.batch_results'), style: AppTheme.sectionLabel),
          const Spacer(),
          Text('${total ?? batchResults.length} ${context.t('rules.test.records_suffix')}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ]),
        const SizedBox(height: 8),
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.bgRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(children: [
            const SizedBox(width: 32, child: Text('#', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
            Expanded(child: Text(context.t('rules.test.matched_rules'),
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
            const SizedBox(width: 60, child: Text('ms', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
          ]),
        ),
        for (final r in batchResults)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgPage,
              border: Border(
                left: const BorderSide(color: AppTheme.borderSubtle),
                right: const BorderSide(color: AppTheme.borderSubtle),
                bottom: const BorderSide(color: AppTheme.borderSubtle),
              ),
            ),
            child: Row(children: [
              SizedBox(width: 32,
                child: Text('${(r as Map)['record_index'] + 1}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(
                child: Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final m in (r['matched_rules'] as List?) ?? [])
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: AppTheme.pill(
                        bg: (m as Map)['path'] == 'else' ? AppTheme.warningBg : AppTheme.successBg,
                        border: m['path'] == 'else' ? AppTheme.warningBorder : AppTheme.successBorder,
                      ),
                      child: Text(
                        '${m['rule_name']}${m['path'] == 'else' ? ' (else)' : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          color: m['path'] == 'else' ? AppTheme.warningText : AppTheme.successText,
                        ),
                      ),
                    ),
                  if ((r['matched_rules'] as List?)?.isEmpty ?? true)
                    const Text('—', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ]),
              ),
              SizedBox(width: 60,
                child: Text('${r['elapsed_ms']}ms',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
            ]),
          ),
      ],
    ]);
  }
}

class _MatchedRuleResult extends StatelessWidget {
  final Map<String, dynamic> result;
  const _MatchedRuleResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final actions = (result['actions_preview'] as List?) ?? [];
    final elseActions = (result['else_actions_preview'] as List?) ?? [];
    final path = result['path'] as String? ?? 'then';
    final isElse = path == 'else';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isElse ? AppTheme.warningBg : AppTheme.successBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isElse ? AppTheme.warningBorder : AppTheme.successBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isElse ? Icons.do_not_disturb_alt_outlined : Icons.check_circle_outline,
            size: 14,
            color: isElse ? AppTheme.warningText : AppTheme.successText,
          ),
          const SizedBox(width: 6),
          Text(result['rule_name'] as String? ?? '',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isElse ? AppTheme.warningText : AppTheme.successText)),
          const Spacer(),
          if (isElse)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: AppTheme.pill(bg: AppTheme.warningBg, border: AppTheme.warningBorder),
              child: const Text('else path', style: TextStyle(fontSize: 10, color: AppTheme.warningText)),
            )
          else
            Text('priority ${result['priority'] ?? '?'}',
                style: const TextStyle(fontSize: 11, color: AppTheme.successText)),
        ]),
        // Show applicable actions list
        for (final a in [...actions, ...elseActions])
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 4),
            child: Row(children: [
              Icon(Icons.arrow_right, size: 12,
                  color: isElse ? AppTheme.warningText : AppTheme.successText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${a['type']} — ${(a['preview'] as Map?)?.entries.where((e) => e.value.toString().isNotEmpty).map((e) => '${e.key}: ${e.value}').join(', ') ?? ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: isElse ? AppTheme.warningText : AppTheme.successText),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─── AI Rule Generate dialog (Gap 10) ────────────────────────────────────────

class _AIGenerateDialog extends ConsumerStatefulWidget {
  const _AIGenerateDialog();

  @override
  ConsumerState<_AIGenerateDialog> createState() => _AIGenerateDialogState();
}

class _AIGenerateDialogState extends ConsumerState<_AIGenerateDialog> {
  final _descCtrl = TextEditingController();
  final _eventTypeCtrl = TextEditingController(text: 'form_submit');
  bool _generating = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    _eventTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    setState(() { _generating = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/rules/ai-generate', data: {
        'description': desc,
        'event_type': _eventTypeCtrl.text.trim().isNotEmpty
            ? _eventTypeCtrl.text.trim()
            : 'form_submit',
      });
      final data = resp.data as Map<String, dynamic>;
      final rule = data['rule'] as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(rule);
    } catch (e) {
      setState(() { _error = e.toString(); _generating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgSurface,
      child: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.bgRaised,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppTheme.purpleText),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Generate Rule with AI',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textBright)),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop(null),
                child: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
              ),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.purpleBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.purpleBorder),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 13, color: AppTheme.purpleText),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Claude will generate a rule in draft status. Review all fields before publishing.',
                      style: TextStyle(fontSize: 11, color: AppTheme.purpleText),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Event type', style: AppTheme.labelStyle),
              const SizedBox(height: 4),
              TextField(
                controller: _eventTypeCtrl,
                decoration: const InputDecoration(
                  hintText: 'form_submit',
                  hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  filled: true,
                  fillColor: AppTheme.bgRaised,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.codeText),
              ),
              const SizedBox(height: 12),
              Text('Describe the rule in plain English *', style: AppTheme.labelStyle),
              const SizedBox(height: 4),
              TextField(
                controller: _descCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. When a contact form is submitted with a score above 80 and an email from a company domain, '
                      'send an email to sales@example.com and trigger the "High Value Lead" workflow.',
                  hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  isDense: true,
                  contentPadding: EdgeInsets.all(10),
                  filled: true,
                  fillColor: AppTheme.bgRaised,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.errorBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.errorBorder),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 11, color: AppTheme.errorText)),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome, size: 15),
                  label: Text(_generating
                      ? context.t('rules.editor.generating')
                      : context.t('rules.editor.generate_rule')),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.purpleBorder),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}


// ─── Pending Approvals Sheet (Gap 15) ─────────────────────────────────────────

class _PendingApprovalsSheet extends ConsumerStatefulWidget {
  final VoidCallback onApproved;
  const _PendingApprovalsSheet({required this.onApproved});

  @override
  ConsumerState<_PendingApprovalsSheet> createState() => _PendingApprovalsSheetState();
}

class _PendingApprovalsSheetState extends ConsumerState<_PendingApprovalsSheet> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/rules/approvals', queryParameters: {'status': 'pending'});
      setState(() {
        _pending = List<Map<String, dynamic>>.from(resp.data as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _decide(String approvalId, String action) async {
    final tApprovedMsg = context.t('rules.pending_approvals.approved_msg');
    final tRejectedMsg = context.t('rules.pending_approvals.rejected_msg');
    final tErrorPrefix = context.t('rules.pending_approvals.error_prefix');
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/rules/approvals/$approvalId/decide', data: {'action': action});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'approve' ? tApprovedMsg : tRejectedMsg)),
        );
        widget.onApproved();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tErrorPrefix: $e'), backgroundColor: AppTheme.errorBorder),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(children: [
            const Icon(Icons.approval_outlined, size: 16, color: AppTheme.warningText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.t('rules.pending_approvals.title'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textBright)),
            ),
            TextButton(onPressed: () => Navigator.pop(context),
                child: Text(context.t('rules.pending_approvals.close'))),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _pending.isEmpty
                  ? Center(
                      child: Text(context.t('rules.pending_approvals.empty'),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    )
                  : ListView.separated(
                      controller: ctrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _pending.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final ap = _pending[i];
                        final snap = ap['rule_snapshot'] as Map? ?? {};
                        final approvers = (ap['required_approvers'] as List?)?.cast<String>() ?? [];
                        final approvedList = (ap['approvals'] as List?)
                            ?.map((a) => (a as Map)['email'] as String? ?? '')
                            .toList() ?? [];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.bgRaised,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.warningBorder),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(snap['name'] as String? ?? context.t('rules.pending_approvals.rule_fallback'),
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textBright, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text('${context.t('rules.pending_approvals.requested_by')}: ${ap['requested_by'] ?? ''}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(
                              '${context.t('rules.pending_approvals.approvers')}: ${approvers.join(', ')}  '
                              '(${approvedList.length}/${approvers.length} ${context.t('rules.pending_approvals.approved_suffix')})',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 12),
                            Row(children: [
                              FilledButton.icon(
                                onPressed: () => _decide(ap['id'] as String, 'approve'),
                                icon: const Icon(Icons.check, size: 14),
                                label: Text(context.t('rules.pending_approvals.approve'),
                                    style: const TextStyle(fontSize: 12)),
                                style: FilledButton.styleFrom(backgroundColor: AppTheme.successBorder,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7)),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => _decide(ap['id'] as String, 'reject'),
                                icon: const Icon(Icons.close, size: 14, color: AppTheme.errorText),
                                label: Text(context.t('rules.pending_approvals.reject'),
                                    style: const TextStyle(fontSize: 12, color: AppTheme.errorText)),
                                style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppTheme.errorBorder),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7)),
                              ),
                            ]),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
