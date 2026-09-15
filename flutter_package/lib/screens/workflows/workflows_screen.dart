import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../i18n/translate_extension.dart';
import '../../services/api_client.dart';
import '../../theme.dart';
import '../../widgets/common/ai_search_bar.dart';

class WorkflowsScreen extends ConsumerStatefulWidget {
  /// Vertical-app ownership filter. ``null`` (chassis default) lists only
  /// generic platform workflows (``source_app IS NULL`` server-side); a
  /// value like ``'restoration'`` scopes the list — and any workflow
  /// created from here — to that app. This is the entire reuse seam a
  /// domain host (e.g. restoration's admin frontend) needs:
  /// ``WorkflowsScreen(sourceApp: 'restoration')``.
  final String? sourceApp;
  const WorkflowsScreen({super.key, this.sourceApp});
  @override
  ConsumerState<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends ConsumerState<WorkflowsScreen> {
  List<Map<String, dynamic>> _workflows = [];
  List<Map<String, dynamic>>? _aiRows; // Phase H — when set, render these
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
      final resp = await dio.get('/workflows', queryParameters: {
        if (widget.sourceApp != null) 'source_app': widget.sourceApp,
      });
      setState(() {
        _workflows = List<Map<String, dynamic>>.from(resp.data as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> wf) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.put('/workflows/${wf["id"]}',
          data: {'is_active': !(wf['is_active'] as bool? ?? false)});
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('${context.t('common.request_failed')}: $e'),
        ));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> wf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('workflows.delete_title'),
            style: const TextStyle(color: AppTheme.textBright)),
        content: Text(
            '${ctx.t('workflows.delete_prefix')} "${wf["name"]}"? ${ctx.t('common.cannot_be_undone')}',
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
    if (confirmed != true) return;
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/workflows/${wf["id"]}');
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('${context.t('common.request_failed')}: $e'),
        ));
      }
    }
  }

  Future<void> _run(Map<String, dynamic> wf) async {
    // Capture localized prefix BEFORE the await so context is never
    // read across an async gap.
    final tStarted = context.t('workflows.execution_started');
    final dio = ref.read(dioProvider);
    final resp = await dio.post('/workflows/${wf["id"]}/execute', data: {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$tStarted: ${(resp.data["execution_id"] as String).substring(0, 8)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPage,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('nav.workflows'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textBright)),
                const SizedBox(height: 4),
                Text(context.t('workflows.subtitle'),
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ])),
              FilledButton.icon(
                onPressed: () => context.go('/workflows/new'),
                icon: const Icon(Icons.add, size: 16),
                label: Text(context.t('workflows.new_workflow')),
              ),
            ]),
            const SizedBox(height: 16),
            AiSearchBar(
              entity: 'workflows',
              onResults: (rows) => setState(() => _aiRows = rows),
              onClear: () => setState(() => _aiRows = null),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final list = _aiRows ?? _workflows;
    if (_loading && _aiRows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_tree_outlined,
              size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(context.t('workflows.empty_title'),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/workflows/new'),
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.t('workflows.create_first')),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width - 64),
            child: DataTable(
              border: TableBorder.all(color: AppTheme.borderStrong, width: 1),
              headingRowColor:
                  const WidgetStatePropertyAll(AppTheme.bgRaised),
              headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.textBright),
              columnSpacing: 28,
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Trigger')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: list.map(_wfRow).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _wfRow(Map<String, dynamic> wf) {
    final isActive = wf['is_active'] as bool? ?? false;
    final trigger = wf['trigger_type'] as String? ?? 'manual';
    return DataRow(cells: [
      DataCell(Text(wf['name'] as String? ?? context.t('common.untitled'),
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_triggerIcons[trigger] ?? Icons.account_tree_outlined,
            size: 15, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Text(context.t('workflows.trigger.$trigger'),
            style: const TextStyle(color: AppTheme.textSecondary)),
      ])),
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: AppTheme.pill(
          bg: isActive ? AppTheme.successBg : AppTheme.bgRaised,
          border: isActive ? AppTheme.successBorder : AppTheme.borderSubtle,
        ),
        child: Text(
          isActive ? context.t('common.active') : context.t('common.inactive'),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? AppTheme.successText : AppTheme.textMuted),
        ),
      )),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        _ActionBtn(
            icon: Icons.play_arrow_outlined,
            tooltip: context.t('workflows.run_now'),
            onTap: () => _run(wf)),
        _ActionBtn(
            icon: Icons.edit_outlined,
            tooltip: context.t('common.edit'),
            onTap: () => context.go('/workflows/${wf["id"]}/edit')),
        _ActionBtn(
            icon: isActive
                ? Icons.toggle_on_outlined
                : Icons.toggle_off_outlined,
            tooltip: isActive
                ? context.t('common.deactivate')
                : context.t('common.activate'),
            color: isActive ? AppTheme.successText : AppTheme.textMuted,
            onTap: () => _toggleActive(wf)),
        _ActionBtn(
            icon: Icons.delete_outline,
            tooltip: context.t('common.delete'),
            color: AppTheme.errorText,
            onTap: () => _delete(wf)),
      ])),
    ]);
  }
}

const _triggerIcons = <String, IconData>{
  'manual': Icons.touch_app_outlined,
  'webhook': Icons.webhook,
  'cron': Icons.schedule_outlined,
  'imap': Icons.email_outlined,
  'form': Icons.dynamic_form_outlined,
};

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color ?? AppTheme.textSecondary),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    );
  }
}
