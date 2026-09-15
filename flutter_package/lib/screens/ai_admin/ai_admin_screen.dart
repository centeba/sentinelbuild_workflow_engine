import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import '_dark_table_theme.dart';
import '_detail_sheet.dart';
import '_help_banner.dart';
import '_pagination_toolbar.dart';
import 'agent_edit_dialog.dart';
import 'agent_try_dialog.dart' show showAgentTryDialog;
import 'ai_admin_api.dart';
import 'compliance_tab.dart';
import 'platform_keys_tab.dart';
import 'skill_edit_dialog.dart';
import 'tools_tab.dart';
import 'usage_tab.dart';

/// Admin screen for AI agents and skills.
///
/// Server-side every endpoint behind ``/ai-agents`` and ``/ai-skills`` is
/// gated on ``CompanyAdminDep`` so a member that somehow reaches the URL
/// will see 403s. The host's sidebar must also hide the entry from
/// non-admins — see SentinelBuild's app_shell role-filter.
class AiAdminScreen extends ConsumerStatefulWidget {
  /// When embedded in a domain app for a `company_admin`, pass ``false`` to
  /// omit the **Platform keys** tab — that tab configures system-wide LLM
  /// provider keys and is `system_admin`-only (it renders a forbidden state for
  /// anyone else). Company admins create agents/skills that *consume* those
  /// keys; they never see or set them. Defaults to ``true`` (chassis console).
  final bool showPlatformTab;

  const AiAdminScreen({super.key, this.showPlatformTab = true});

  @override
  ConsumerState<AiAdminScreen> createState() => _AiAdminScreenState();
}

class _AiAdminScreenState extends ConsumerState<AiAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: widget.showPlatformTab ? 6 : 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
            Text(context.t('ai_admin.title'),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textBright)),
            const SizedBox(height: 4),
            Text(context.t('ai_admin.subtitle'),
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: [
                Tab(text: context.t('ai_admin.agents_tab')),
                Tab(text: context.t('ai_admin.skills_tab')),
                Tab(text: context.t('ai_admin.tools_tab')),
                Tab(text: context.t('ai_admin.usage_tab')),
                Tab(text: context.t('ai_admin.compliance_tab')),
                // Phase G — system_admin-only; non-admins see the
                // forbidden state inside the tab body. Omitted entirely when
                // embedded for a company_admin (showPlatformTab: false).
                if (widget.showPlatformTab)
                  Tab(text: context.t('ai_admin.platform_tab')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  const _AgentsTab(),
                  const _SkillsTab(),
                  const ToolsTab(),
                  const UsageTab(),
                  const ComplianceTab(),
                  if (widget.showPlatformTab) const PlatformKeysTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Agents tab ────────────────────────────────────────────────────────────────

class _AgentsTab extends ConsumerStatefulWidget {
  const _AgentsTab();
  @override
  ConsumerState<_AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends ConsumerState<_AgentsTab> {
  // Persistent source — mutated in-place + notifyListeners() so
  // PaginatedDataTable re-renders. Recreating the source on every
  // setState (the previous shape) lost selection/page state and, more
  // importantly, sometimes failed to repaint at all because the
  // internal listener was attached to the *previous* instance.
  late final _AgentsDataSource _source;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;

  // When false (default), the list is scoped server-side to the admin's
  // own company + platform-scoped agents. Toggling on opts into the full
  // cross-tenant list (every tenant's per-company seeded agents).
  bool _allCompanies = false;

  // Default sort: by Name (label) ascending. Column indices below
  // match the order of `columns` in build().
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  // Pagination — controls live in a top toolbar (PaginationToolbar)
  // and we render via plain DataTable. We dropped PaginatedDataTable
  // because it hard-codes its controls into a footer below the rows.
  int _pageIndex = 0;
  int _pageSize = 50;

  // Phase M — debouncer for ES search. Cancels in-flight typing so
  // we don't hammer the backend on every keystroke.
  Timer? _esDebounce;
  int _esRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    _source = _AgentsDataSource(
      onShowDetail: _showDetail,
      onEdit: _edit,
      onDelete: _delete,
      onTry: _try,
    );
    _load();
  }

  @override
  void dispose() {
    _esDebounce?.cancel();
    _searchCtrl.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(aiAdminApiProvider)
          .listAgents(allCompanies: _allCompanies);
      if (!mounted) return;
      _source.setRows(list);
      // Re-apply current sort so the freshly-loaded rows respect the
      // user's last column choice instead of snapping back to API order.
      _applySort();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Phase M — debounced server-side ES search. When the user types,
  /// schedule an `/ai-search/admin?type=agent` call ~250 ms after the
  /// last keystroke; on response, narrow the in-memory source to the
  /// returned id set. Empty/error response leaves the in-memory
  /// substring filter as the sole source of truth.
  void _scheduleEsSearch(String q) {
    _esDebounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      _source.setEsNarrow(null);
      return;
    }
    final seq = ++_esRequestSeq;
    _esDebounce = Timer(const Duration(milliseconds: 250), () async {
      final api = ref.read(aiAdminApiProvider);
      final rows = await api.searchAdmin(query, type: 'agent', limit: 100);
      // Ignore stale responses (the user kept typing after this fired).
      if (!mounted || seq != _esRequestSeq) return;
      if (rows.isEmpty) {
        // No ES matches OR ES unreachable — fall back silently to
        // the in-memory substring filter (already running).
        _source.setEsNarrow(null);
        return;
      }
      final ids = rows
          .map((r) => (r['id'] as Object?)?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      _source.setEsNarrow(ids);
    });
  }

  /// True when the agent row was provisioned by a vertical app's AgentBundle
  /// sync. Same read-only treatment as managed skills: server returns 403 on
  /// PATCH/DELETE; UI here gives a better UX.
  bool _isManaged(Map<String, dynamic> row) =>
      (row['source_app'] ?? '').toString().isNotEmpty;

  /// Phase E3 — open the Try-It dialog for ``row``. The dialog
  /// holds its own state + stream subscription; we just hand off the
  /// agent and let it run.
  Future<void> _try(Map<String, dynamic> row) async {
    await showAgentTryDialog(context, agent: row);
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (row != null && _isManaged(row)) {
      // Managed agents can't be edited here. Show the read-only detail
      // sheet so the admin can still inspect provider/model/skills.
      _showDetail(row);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AgentEditDialog(agent: row),
    );
    if (saved == true) _load();
  }

  void _showDetail(Map<String, dynamic> row) {
    final skills = ((row['skills'] as List?) ?? const [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => DetailSheet(
        kind: DetailKind.agent,
        row: row,
        attachedSkills: skills,
      ),
    );
  }

  /// Comparable extractors per column index. Indices match the
  /// ``columns`` list in build(); the actions column has no entry.
  Comparable<dynamic> Function(Map<String, dynamic>) _getterFor(int columnIndex) {
    switch (columnIndex) {
      case 0:
        return (r) => (r['label'] ?? r['name'] ?? '').toString().toLowerCase();
      case 1:
        return (r) => (r['provider_type'] ?? '').toString();
      case 2:
        return (r) => (r['model_name'] ?? '').toString();
      case 3:
        return (r) => ((r['skills'] as List?)?.length ?? 0);
      case 4:
        return (r) => ((r['is_active'] ?? true) ? 1 : 0);
      default:
        return (r) => 0;
    }
  }

  void _applySort() {
    _source.sortBy(_getterFor(_sortColumnIndex), _sortAscending);
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
    _source.sortBy(_getterFor(columnIndex), ascending);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (_isManaged(row)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.t('ai_admin.cannot_delete_prefix')} "${row['name']}" — '
            '${context.t('ai_admin.cell.domain_managed')}. '
            '${context.t('ai_admin.remove_yaml_hint')}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('ai_admin.delete_agent_title')),
        content: Text(
            '"${row['name']}" ${ctx.t('ai_admin.permanently_removed_suffix')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t('common.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(aiAdminApiProvider).deleteAgent(row['id'].toString());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Body / cell / header colours that read against the dark page bg.
    // Pulled into a single block so every Text in the table inherits a
    // visible colour rather than the Material default which renders
    // near-black on the forced-dark scaffold.
    const cellStyle   = TextStyle(color: AppTheme.textBright, fontSize: 13);
    const headerStyle = TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${context.t('common.error_prefix')}: $_error',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // "New" button moved to top-right per UX feedback.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.t('ai_admin.new_agent')),
            ),
          ),
        ),
        const HelpBanner(kind: HelpBannerKind.agents),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (q) {
              _source.setQuery(q);
              setState(() => _pageIndex = 0);
              _scheduleEsSearch(q);
            },
            decoration: InputDecoration(
              hintText: context.t('ai_admin.search_agents_hint'),
              prefixIcon:
                  const Icon(Icons.search, size: 18, color: AppTheme.textSecondary),
              isDense: true,
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppTheme.textSecondary),
                      onPressed: () {
                        _searchCtrl.clear();
                        _source.setQuery('');
                        setState(() => _pageIndex = 0);
                        _esDebounce?.cancel();
                        _source.setEsNarrow(null);
                      },
                    ),
            ),
          ),
        ),
        // Platform-admin scope toggle. Off (default) = own company +
        // platform-scoped agents only; On = every tenant's agents (noisy).
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
          child: Row(
            children: [
              Checkbox(
                value: _allCompanies,
                visualDensity: VisualDensity.compact,
                onChanged: (v) {
                  setState(() {
                    _allCompanies = v ?? false;
                    _pageIndex = 0;
                  });
                  _load();
                },
              ),
              const Text(
                'Show all companies',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 6),
              const Tooltip(
                message:
                    'Off: your company + platform agents only.\n'
                    'On: every tenant\'s agents (each company has its own '
                    'seeded defaults, so names repeat).',
                child: Icon(Icons.info_outline,
                    size: 15, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        if (_source.rowCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(context.t('ai_admin.no_agents'),
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
          )
        else
          // No outer SingleChildScrollView — Flutter's gesture arena
          // treats every tap inside a horizontal SingleChildScrollView
          // as a potential drag-start, the scroll view wins the
          // gesture race, and DataCell.onTap / IconButton.onPressed
          // never fire. PaginatedDataTable has its own internal
          // horizontal scroll for the data area, so the wrapper was
          // redundant and the outright cause of the dead row taps.
          // AnimatedBuilder rebuilds when the source's
          // ``notifyListeners()`` fires (sort/filter/load). Plain
          // DataTable below it gets a sliced page of rows.
          AnimatedBuilder(
            animation: _source,
            builder: (context, _) {
              _source.cellStyle = cellStyle;
              // Phase L3-deep-2: thread localized strings into the
              // DataSource so the cell tooltips can use them.
              _source.loc = (
                noDescription: context.t('ai_admin.cell.no_description'),
                noSkillsAttached: context.t('agent_node.no_skills'),
                editTooltip: context.t('common.edit'),
                deleteTooltip: context.t('common.delete'),
                tryTooltip: context.t('ai_admin.try_it.tooltip'),
                domainLabel: context.t('ai_admin.cell.domain'),
                // No domain name in the tooltips — ``src`` is ignored.
                viewManagedTooltip: (src) => context.t('ai_admin.cell.view_domain'),
                managedTooltip: (src) =>
                    '${context.t('ai_admin.cell.domain_managed')} — '
                    '${context.t('ai_admin.cell.managed_hint')}',
              );
              final total = _source.rowCount;
              // Clamp the page index whenever rowCount changes (e.g.
              // after a filter narrows the result set).
              final lastPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
              if (_pageIndex > lastPage) _pageIndex = lastPage;
              final start = _pageIndex * _pageSize;
              final end = (start + _pageSize).clamp(0, total);
              final pageRows = <DataRow>[
                for (var i = start; i < end; i++) _source.getRow(i)!,
              ];
              return darkenedTable(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PaginationToolbar(
                      rowCount: total,
                      pageIndex: _pageIndex,
                      pageSize: _pageSize,
                      onFirst: () => setState(() => _pageIndex = 0),
                      onPrev: () => setState(() => _pageIndex--),
                      onNext: () => setState(() => _pageIndex++),
                      onLast: () => setState(() => _pageIndex = lastPage),
                      onPageSizeChange: (n) => setState(() {
                        _pageSize = n;
                        _pageIndex = 0;
                      }),
                    ),
                    DataTable(
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      columnSpacing: 32,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 56,
                      border: TableBorder.all(
                          color: AppTheme.borderStrong, width: 1),
                      headingRowColor: const WidgetStatePropertyAll(
                          AppTheme.bgRaised),
                      columns: [
                        DataColumn(
                            label: Text(context.t('ai_admin.col_name'), style: headerStyle),
                            onSort: _onSort),
                        // Phase G — scope chip column (company / platform / shared).
                        DataColumn(
                            label: Text(context.t('ai_admin.col_scope'),
                                style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_provider'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_model'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_skills'), style: headerStyle),
                            numeric: true,
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('common.active'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(label: Text('', style: headerStyle)),
                      ],
                      rows: pageRows,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Persistent backing source for the paginated agents table.
///
/// Why a stateful source instead of recreating-on-rebuild: when sort
/// or reload runs, we mutate ``_rows`` in place and call
/// ``notifyListeners()``. PaginatedDataTable subscribes to that
/// signal — without it, the table doesn't know data shifted and the
/// sort arrow flips while rows stay put. Recreating the source on
/// every parent setState (the previous shape) sometimes worked and
/// sometimes didn't, depending on whether PaginatedDataTable's
/// ``didUpdateWidget`` rewired its listener in time.
class _AgentsDataSource extends DataTableSource {
  _AgentsDataSource({
    required this.onShowDetail,
    required this.onEdit,
    required this.onDelete,
    required this.onTry,
  });

  // ``_allRows`` is the full API result; ``_rows`` is the
  // sorted-and-filtered view actually rendered. Splitting them lets
  // ``setQuery`` re-apply against the unfiltered source without
  // re-fetching from the API on every keystroke.
  final List<Map<String, dynamic>> _allRows = [];
  final List<Map<String, dynamic>> _rows = [];
  String _query = '';
  Comparable<dynamic> Function(Map<String, dynamic>)? _lastSorter;
  bool _lastAscending = true;

  TextStyle cellStyle = const TextStyle(color: AppTheme.textBright, fontSize: 13);

  /// Phase L3-deep-2 — localized strings threaded in from the parent
  /// State (where ``BuildContext`` is available). The DataSource lives
  /// outside the widget tree so it can't call ``context.t()`` itself.
  /// Defaults below are English so the panel renders even before the
  /// host injects translations.
  ({
    String noDescription,
    String noSkillsAttached,
    String editTooltip,
    String deleteTooltip,
    String tryTooltip,
    // Generic "Domain" chip label — deliberately does NOT include the domain
    // name (in a single-domain deployment the name is redundant, and we don't
    // surface which domain a row belongs to).
    String domainLabel,
    String Function(String src) viewManagedTooltip,
    String Function(String src) managedTooltip,
  }) loc = (
    noDescription: '(no description)',
    noSkillsAttached: 'No skills attached',
    editTooltip: 'Edit',
    deleteTooltip: 'Delete',
    tryTooltip: 'Try it (live token stream)',
    domainLabel: 'Domain',
    // ``src`` is ignored on purpose — no domain name in the UI.
    viewManagedTooltip: (src) => 'View (domain-managed)',
    managedTooltip: (src) =>
        'Domain-managed — edit the YAML in the domain app and redeploy.',
  );

  final void Function(Map<String, dynamic>) onShowDetail;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  // Phase E3 — opens the Try-It dialog (live token stream from the
  // agent). Available on every row, including managed/source_app
  // agents — running an agent doesn't mutate it.
  final Future<void> Function(Map<String, dynamic>) onTry;

  void setRows(List<Map<String, dynamic>> rows) {
    _allRows
      ..clear()
      ..addAll(rows);
    _rebuild();
  }

  void setQuery(String q) {
    _query = q.toLowerCase().trim();
    if (_query.isEmpty) {
      // Empty query clears the ES narrow too — otherwise an old ES
      // result set could keep restricting the table after the user
      // emptied the search field.
      _esNarrow = null;
    }
    _rebuild();
  }

  /// Phase M — narrow visible rows to the set of ids the AI-search
  /// backend matched for the current query. ``null`` disables the
  /// narrow (in-memory client filter alone). Empty set still narrows
  /// (rare — ES would normally just omit the field), so callers
  /// passing an empty set explicitly intend "zero results".
  void setEsNarrow(Set<String>? ids) {
    _esNarrow = ids;
    _rebuild();
  }

  Set<String>? _esNarrow;

  void sortBy(
    Comparable<dynamic> Function(Map<String, dynamic>) getter,
    bool ascending,
  ) {
    _lastSorter = getter;
    _lastAscending = ascending;
    _rebuild();
  }

  /// Re-applies filter + sort against ``_allRows``. Cheaper than
  /// re-fetching from the API on every keystroke / column click.
  void _rebuild() {
    _rows.clear();
    if (_query.isEmpty) {
      _rows.addAll(_allRows);
    } else {
      _rows.addAll(_allRows.where(_matches));
    }
    // Phase M — if ES returned a non-null id set, intersect.
    // Non-empty set = real ES match; restrict. Empty set = "ES
    // explicitly returned no rows" — show empty. Null = disabled.
    if (_esNarrow != null) {
      final ids = _esNarrow!;
      _rows.removeWhere((r) => !ids.contains(r['id']?.toString() ?? ''));
    }
    if (_lastSorter != null) {
      final getter = _lastSorter!;
      final asc = _lastAscending;
      _rows.sort((a, b) {
        final av = getter(a);
        final bv = getter(b);
        return asc ? av.compareTo(bv) : bv.compareTo(av);
      });
    }
    notifyListeners();
  }

  bool _matches(Map<String, dynamic> r) {
    // Substring match across ``name``, ``label``, ``description``,
    // ``provider_type``, ``model_name`` — covers everything the
    // table cells render plus the description shown in the hover
    // tooltip.
    final hay = (
      (r['name'] ?? '').toString() + ' ' +
      (r['label'] ?? '').toString() + ' ' +
      (r['description'] ?? '').toString() + ' ' +
      (r['provider_type'] ?? '').toString() + ' ' +
      (r['model_name'] ?? '').toString()
    ).toLowerCase();
    return hay.contains(_query);
  }

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final r = _rows[index];
    final skills =
        ((r['skills'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final desc = (r['description'] ?? '').toString();
    final skillsTooltip = skills.isEmpty
        ? loc.noSkillsAttached
        : skills
            .map((s) => (s['label'] ?? s['name'] ?? '').toString())
            .join('\n');
    final nameTooltip = desc.isEmpty ? loc.noDescription : desc;
    final sourceApp = (r['source_app'] ?? '').toString();
    final isManaged = sourceApp.isNotEmpty;
    final managedTooltip = loc.managedTooltip(sourceApp);

    return DataRow(cells: [
      DataCell(
        // SizedBox + Container expands the Tooltip hit area to the
        // full cell width — without this the tooltip only fires when
        // the cursor is over the actual text characters.
        SizedBox(
          width: 240,
          child: Tooltip(
            message: nameTooltip,
            waitDuration: const Duration(milliseconds: 250),
            child: Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isManaged) ...[
                    Tooltip(
                      message: managedTooltip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 11, color: AppTheme.textSecondary),
                            const SizedBox(width: 3),
                            Text(
                              // Generic "Domain" label — never the domain name.
                              loc.domainLabel,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      r['label'] ?? r['name'] ?? '',
                      style: cellStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        onTap: () => onShowDetail(r),
      ),
      // Phase G — scope chip.
      DataCell(_ScopeChip(scope: r['scope']?.toString() ?? 'company')),
      DataCell(Text(r['provider_type'] ?? '', style: cellStyle)),
      DataCell(Text(r['model_name'] ?? '', style: cellStyle)),
      DataCell(
        Tooltip(
          message: skillsTooltip,
          waitDuration: const Duration(milliseconds: 250),
          child: Container(
            width: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('${skills.length}', style: cellStyle),
          ),
        ),
      ),
      DataCell(Icon(
        (r['is_active'] ?? true) ? Icons.check : Icons.close,
        size: 16,
        color: AppTheme.textBright,
      )),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        // Explicit Material+InkWell pattern. IconButton inside a
        // narrow auto-sized DataColumn occasionally swallows taps in
        // Material 3 — likely a hit-test interaction with the
        // surrounding DataCell layout. This shape is bullet-proof.
        // Phase E3 — Try-It (live token stream). Available on every
        // row including managed source_app agents (running doesn't
        // mutate config).
        _ActionButton(
          icon: Icons.play_arrow_outlined,
          tooltip: loc.tryTooltip,
          onTap: () => onTry(r),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: isManaged ? Icons.visibility_outlined : Icons.edit,
          tooltip: isManaged ? loc.viewManagedTooltip(sourceApp) : loc.editTooltip,
          onTap: () => onEdit(r),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.delete_outline,
          tooltip: isManaged ? managedTooltip : loc.deleteTooltip,
          onTap: isManaged ? null : () => onDelete(r),
        ),
      ])),
    ]);
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => _rows.length;
  @override
  int get selectedRowCount => 0;
}

// ── Skills tab ────────────────────────────────────────────────────────────────

class _SkillsTab extends ConsumerStatefulWidget {
  const _SkillsTab();
  @override
  ConsumerState<_SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends ConsumerState<_SkillsTab> {
  late final _SkillsDataSource _source;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;

  // Off (default) = own company + platform-scoped skills; On = every
  // tenant's skills (each company has its own seeded copies).
  bool _allCompanies = false;

  /// Cache of registry name → params_schema. Populated lazily when
  /// the user taps a kind=python_tool skill so the detail drawer can
  /// surface typed-arg fields. ``listRegistry`` is fetched once and
  /// reused across taps.
  Map<String, Map<String, dynamic>>? _registryByName;

  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  // Top-toolbar pagination — same pattern as the Agents tab.
  int _pageIndex = 0;
  int _pageSize = 50;

  // Phase M — ES debouncer mirror.
  Timer? _esDebounce;
  int _esRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    _source = _SkillsDataSource(
      onShowDetail: _showDetail,
      onEdit: _edit,
      onDelete: _delete,
    );
    _load();
  }

  @override
  void dispose() {
    _esDebounce?.cancel();
    _searchCtrl.dispose();
    _source.dispose();
    super.dispose();
  }

  void _scheduleEsSearch(String q) {
    _esDebounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      _source.setEsNarrow(null);
      return;
    }
    final seq = ++_esRequestSeq;
    _esDebounce = Timer(const Duration(milliseconds: 250), () async {
      final api = ref.read(aiAdminApiProvider);
      final rows = await api.searchAdmin(query, type: 'skill', limit: 100);
      if (!mounted || seq != _esRequestSeq) return;
      if (rows.isEmpty) {
        _source.setEsNarrow(null);
        return;
      }
      final ids = rows
          .map((r) => (r['id'] as Object?)?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      _source.setEsNarrow(ids);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(aiAdminApiProvider)
          .listSkills(allCompanies: _allCompanies);
      if (!mounted) return;
      _source.setRows(list);
      _applySort();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// True when the skill row was provisioned by a vertical app's SkillBundle
  /// sync — those rows are read-only here; admins must edit the YAML in the
  /// vertical's repo and redeploy. Server-side PATCH/DELETE return 403 with
  /// `error: managed_skill`; this UI guard just gives a better UX.
  bool _isManaged(Map<String, dynamic> row) =>
      (row['source_app'] ?? '').toString().isNotEmpty;

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (row != null && _isManaged(row)) {
      // Managed skills can't be edited here. Show the read-only detail
      // instead so the admin can still inspect the prompt content.
      await _showDetail(row);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SkillEditDialog(skill: row),
    );
    if (saved == true) _load();
  }

  Future<void> _ensureRegistryLoaded() async {
    if (_registryByName != null) return;
    try {
      final list = await ref.read(aiAdminApiProvider).listRegistry();
      _registryByName = {
        for (final t in list) (t['name'] ?? '').toString(): t,
      };
    } catch (_) {
      _registryByName = const {};
    }
  }

  Future<void> _showDetail(Map<String, dynamic> row) async {
    final kind = (row['kind'] ?? 'prompt').toString();
    Map<String, dynamic>? schema;
    if (kind == 'python_tool') {
      await _ensureRegistryLoaded();
      // ``content`` (the registry key) takes precedence over
      // ``name`` because admins sometimes rename the AISkill row's
      // ``name`` while keeping ``content`` pinned to the registry
      // entry. Fall back to name if content is empty.
      final regKey = ((row['content'] ?? '').toString().isNotEmpty
              ? row['content']
              : row['name'])
          .toString();
      final entry = _registryByName?[regKey];
      schema = entry?['params_schema'] as Map<String, dynamic>?;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => DetailSheet(
        kind: kind == 'python_tool'
            ? DetailKind.skillPythonTool
            : DetailKind.skillPrompt,
        row: row,
        paramsSchema: schema,
      ),
    );
  }

  Comparable<dynamic> Function(Map<String, dynamic>) _getterFor(int columnIndex) {
    switch (columnIndex) {
      case 0:
        return (r) => (r['label'] ?? r['name'] ?? '').toString().toLowerCase();
      case 1:
        return (r) => (r['modality'] ?? 'any').toString();
      case 2:
        return (r) => (r['kind'] ?? 'prompt').toString();
      case 3:
        return (r) => ((r['is_active'] ?? true) ? 1 : 0);
      default:
        return (r) => 0;
    }
  }

  void _applySort() {
    _source.sortBy(_getterFor(_sortColumnIndex), _sortAscending);
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
    _source.sortBy(_getterFor(columnIndex), ascending);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (_isManaged(row)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.t('ai_admin.cannot_delete_prefix')} "${row['name']}" — '
            '${context.t('ai_admin.cell.domain_managed')}. '
            '${context.t('ai_admin.remove_yaml_hint')}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('ai_admin.delete_skill_title')),
        content: Text(
            '"${row['name']}" ${ctx.t('ai_admin.permanently_removed_suffix')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t('common.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(aiAdminApiProvider).deleteSkill(row['id'].toString());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    const cellStyle   = TextStyle(color: AppTheme.textBright, fontSize: 13);
    const headerStyle = TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${context.t('common.error_prefix')}: $_error',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.t('ai_admin.new_skill')),
            ),
          ),
        ),
        const HelpBanner(kind: HelpBannerKind.skills),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (q) {
              _source.setQuery(q);
              setState(() => _pageIndex = 0);
              _scheduleEsSearch(q);
            },
            decoration: InputDecoration(
              hintText: context.t('ai_admin.search_skills_hint'),
              prefixIcon:
                  const Icon(Icons.search, size: 18, color: AppTheme.textSecondary),
              isDense: true,
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppTheme.textSecondary),
                      onPressed: () {
                        _searchCtrl.clear();
                        _source.setQuery('');
                        setState(() => _pageIndex = 0);
                        _esDebounce?.cancel();
                        _source.setEsNarrow(null);
                      },
                    ),
            ),
          ),
        ),
        // Platform-admin scope toggle (mirrors the Agents tab).
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
          child: Row(
            children: [
              Checkbox(
                value: _allCompanies,
                visualDensity: VisualDensity.compact,
                onChanged: (v) {
                  setState(() {
                    _allCompanies = v ?? false;
                    _pageIndex = 0;
                  });
                  _load();
                },
              ),
              const Text(
                'Show all companies',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 6),
              const Tooltip(
                message:
                    'Off: your company + platform skills only.\n'
                    'On: every tenant\'s skills (each company has its own '
                    'seeded copies, so names repeat).',
                child: Icon(Icons.info_outline,
                    size: 15, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        if (_source.rowCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(context.t('ai_admin.no_skills'),
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
          )
        else
          AnimatedBuilder(
            animation: _source,
            builder: (context, _) {
              _source.cellStyle = cellStyle;
              // Phase L3-deep-2: thread localized strings into the
              // skills DataSource (mirrors the agents tab).
              _source.loc = (
                noDescription: context.t('ai_admin.cell.no_description'),
                editTooltip: context.t('common.edit'),
                deleteTooltip: context.t('common.delete'),
                domainLabel: context.t('ai_admin.cell.domain'),
                // No domain name in the tooltips — ``src`` is ignored.
                viewManagedTooltip: (src) => context.t('ai_admin.cell.view_domain'),
                managedTooltip: (src) =>
                    '${context.t('ai_admin.cell.domain_managed')} — '
                    '${context.t('ai_admin.cell.managed_hint')}',
              );
              final total = _source.rowCount;
              final lastPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
              if (_pageIndex > lastPage) _pageIndex = lastPage;
              final start = _pageIndex * _pageSize;
              final end = (start + _pageSize).clamp(0, total);
              final pageRows = <DataRow>[
                for (var i = start; i < end; i++) _source.getRow(i)!,
              ];
              return darkenedTable(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PaginationToolbar(
                      rowCount: total,
                      pageIndex: _pageIndex,
                      pageSize: _pageSize,
                      onFirst: () => setState(() => _pageIndex = 0),
                      onPrev: () => setState(() => _pageIndex--),
                      onNext: () => setState(() => _pageIndex++),
                      onLast: () => setState(() => _pageIndex = lastPage),
                      onPageSizeChange: (n) => setState(() {
                        _pageSize = n;
                        _pageIndex = 0;
                      }),
                    ),
                    DataTable(
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      columnSpacing: 32,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 56,
                      border: TableBorder.all(
                          color: AppTheme.borderStrong, width: 1),
                      headingRowColor: const WidgetStatePropertyAll(
                          AppTheme.bgRaised),
                      columns: [
                        DataColumn(
                            label: Text(context.t('ai_admin.col_name'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_modality'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_kind'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('common.active'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(label: Text('', style: headerStyle)),
                      ],
                      rows: pageRows,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _SkillsDataSource extends DataTableSource {
  _SkillsDataSource({
    required this.onShowDetail,
    required this.onEdit,
    required this.onDelete,
  });

  // Same filter+sort pattern as _AgentsDataSource — see comment there.
  final List<Map<String, dynamic>> _allRows = [];
  final List<Map<String, dynamic>> _rows = [];
  String _query = '';
  Comparable<dynamic> Function(Map<String, dynamic>)? _lastSorter;
  bool _lastAscending = true;

  TextStyle cellStyle = const TextStyle(color: AppTheme.textBright, fontSize: 13);

  /// Phase L3-deep-2 — see _AgentsDataSource for the same pattern.
  ({
    String noDescription,
    String editTooltip,
    String deleteTooltip,
    String domainLabel,
    String Function(String src) viewManagedTooltip,
    String Function(String src) managedTooltip,
  }) loc = (
    noDescription: '(no description)',
    editTooltip: 'Edit',
    deleteTooltip: 'Delete',
    domainLabel: 'Domain',
    // ``src`` is ignored on purpose — no domain name in the UI.
    viewManagedTooltip: (src) => 'View (domain-managed)',
    managedTooltip: (src) =>
        'Domain-managed — edit the YAML in the domain app and redeploy.',
  );

  final Future<void> Function(Map<String, dynamic>) onShowDetail;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  void setRows(List<Map<String, dynamic>> rows) {
    _allRows
      ..clear()
      ..addAll(rows);
    _rebuild();
  }

  void setQuery(String q) {
    _query = q.toLowerCase().trim();
    if (_query.isEmpty) {
      _esNarrow = null;
    }
    _rebuild();
  }

  /// Phase M — see _AgentsDataSource.setEsNarrow for semantics.
  void setEsNarrow(Set<String>? ids) {
    _esNarrow = ids;
    _rebuild();
  }

  Set<String>? _esNarrow;

  void sortBy(
    Comparable<dynamic> Function(Map<String, dynamic>) getter,
    bool ascending,
  ) {
    _lastSorter = getter;
    _lastAscending = ascending;
    _rebuild();
  }

  void _rebuild() {
    _rows.clear();
    if (_query.isEmpty) {
      _rows.addAll(_allRows);
    } else {
      _rows.addAll(_allRows.where(_matches));
    }
    if (_esNarrow != null) {
      final ids = _esNarrow!;
      _rows.removeWhere((r) => !ids.contains(r['id']?.toString() ?? ''));
    }
    if (_lastSorter != null) {
      final getter = _lastSorter!;
      final asc = _lastAscending;
      _rows.sort((a, b) {
        final av = getter(a);
        final bv = getter(b);
        return asc ? av.compareTo(bv) : bv.compareTo(av);
      });
    }
    notifyListeners();
  }

  bool _matches(Map<String, dynamic> r) {
    final hay = (
      (r['name'] ?? '').toString() + ' ' +
      (r['label'] ?? '').toString() + ' ' +
      (r['description'] ?? '').toString() + ' ' +
      (r['kind'] ?? '').toString() + ' ' +
      (r['modality'] ?? '').toString()
    ).toLowerCase();
    return hay.contains(_query);
  }

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final r = _rows[index];
    final desc = (r['description'] ?? '').toString();
    final tooltipMsg = desc.isEmpty ? loc.noDescription : desc;
    final sourceApp = (r['source_app'] ?? '').toString();
    final isManaged = sourceApp.isNotEmpty;
    final managedTooltip = loc.managedTooltip(sourceApp);

    return DataRow(cells: [
      DataCell(
        SizedBox(
          width: 240,
          child: Tooltip(
            message: tooltipMsg,
            waitDuration: const Duration(milliseconds: 250),
            child: Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isManaged) ...[
                    // Lock + source-app badge identifies vertical-app skills
                    // at a glance without burning a whole new column.
                    Tooltip(
                      message: managedTooltip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 11, color: AppTheme.textSecondary),
                            const SizedBox(width: 3),
                            Text(
                              // Generic "Domain" label — never the domain name.
                              loc.domainLabel,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      r['label'] ?? r['name'] ?? '',
                      style: cellStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        onTap: () => onShowDetail(r),
      ),
      DataCell(Text(r['modality'] ?? 'any', style: cellStyle)),
      DataCell(Text(r['kind'] ?? 'prompt', style: cellStyle)),
      DataCell(Icon(
        (r['is_active'] ?? true) ? Icons.check : Icons.close,
        size: 16,
        color: AppTheme.textBright,
      )),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        _ActionButton(
          // Managed rows are view-only — clicking still goes to onEdit but
          // the parent re-routes to the detail sheet (see _SkillsTabState._edit).
          icon: isManaged ? Icons.visibility_outlined : Icons.edit,
          tooltip: isManaged ? loc.viewManagedTooltip(sourceApp) : loc.editTooltip,
          onTap: () => onEdit(r),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.delete_outline,
          tooltip: isManaged ? managedTooltip : loc.deleteTooltip,
          // Disable the visual + tap for managed rows; the parent's _delete
          // also short-circuits with a snackbar as defense-in-depth.
          onTap: isManaged ? null : () => onDelete(r),
        ),
      ])),
    ]);
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => _rows.length;
  @override
  int get selectedRowCount => 0;
}

/// Small action button used in the row-actions cell of Agents/Skills.
///
/// Why not ``IconButton``: empirical — the stock IconButton sometimes
/// fails to fire its onPressed when packed into a narrow auto-sized
/// DataColumn alongside another IconButton inside a DataCell. Symptom
/// is silent — no ripple, no log, no crash. Replacing with explicit
/// ``Material(color: transparent) + InkWell`` with a fixed 32×32 size
/// box restores reliable hit-testing and ripple feedback.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  // Nullable so callers can render a disabled state — used for managed
  // skills where Edit/Delete don't apply (the YAML in the source app is
  // the source of truth).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final iconColor = disabled
        ? AppTheme.textSecondary.withOpacity(0.4)
        : AppTheme.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Icon(icon, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}


/// Phase G — small chip rendering an agent's visibility scope.
/// Three colour-coded variants: ``company`` (subtle), ``platform``
/// (accent), ``shared`` (warn-ish). Unknown values fall through to
/// the company shape so the UI doesn't crash on a future scope.
class _ScopeChip extends StatelessWidget {
  final String scope;
  const _ScopeChip({required this.scope});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (scope) {
      'platform' => (
        context.t('ai_admin.scope.platform'),
        const Color(0xFF1E3A5F),  // muted blue
        const Color(0xFF89B8FF),
      ),
      'shared' => (
        context.t('ai_admin.scope.shared'),
        const Color(0xFF4A3A1F),  // muted amber
        const Color(0xFFE8B86A),
      ),
      _ => (
        context.t('ai_admin.scope.company'),
        AppTheme.bgRaised,
        AppTheme.textSecondary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
