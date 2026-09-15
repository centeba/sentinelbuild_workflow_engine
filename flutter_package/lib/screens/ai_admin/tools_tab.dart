import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import '_dark_table_theme.dart';
import '_detail_sheet.dart';
import '_help_banner.dart';
import '_pagination_toolbar.dart';
import 'ai_admin_api.dart';

/// Read-only catalogue of every Python tool class currently registered
/// in :mod:`smart_llm.registry`. Distinct from the Skills tab which
/// lists per-tenant ``ai_skills`` rows — the Tools tab is the
/// *registry* itself, independent of seed migrations.
class ToolsTab extends ConsumerStatefulWidget {
  const ToolsTab({super.key});

  @override
  ConsumerState<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends ConsumerState<ToolsTab> {
  late final _ToolsDataSource _source;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;

  // Default sort: by Modality then Name (column index 2 = Modality
  // when the column list is Name|Label|Modality|Kind|Params).
  int _sortColumnIndex = 2;
  bool _sortAscending = true;
  int _pageIndex = 0;
  int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _source = _ToolsDataSource(onTap: _showDetail);
    _load();
  }

  @override
  void dispose() {
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
      final list = await ref.read(aiAdminApiProvider).listRegistry();
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

  void _showDetail(Map<String, dynamic> row) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => DetailSheet(
        kind: DetailKind.tool,
        row: row,
        paramsSchema: row['params_schema'] as Map<String, dynamic>?,
      ),
    );
  }

  Comparable<dynamic> Function(Map<String, dynamic>) _getterFor(int columnIndex) {
    switch (columnIndex) {
      case 0:
        return (r) => (r['name'] ?? '').toString();
      case 1:
        return (r) => (r['label'] ?? '').toString().toLowerCase();
      case 2:
        return (r) => (r['modality'] ?? 'any').toString();
      case 3:
        return (r) => (r['kind'] ?? 'python_tool').toString();
      case 4:
        // Params count — no schema means 0.
        return (r) =>
            (r['params_schema'] is Map<String, dynamic>
                    ? ((r['params_schema'] as Map<String, dynamic>)['properties']
                            as Map<String, dynamic>?)
                        ?.length
                    : 0) ??
                0;
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

  @override
  Widget build(BuildContext context) {
    const cellStyle = TextStyle(color: AppTheme.textBright, fontSize: 13);
    const headerStyle = TextStyle(
        color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $_error',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const HelpBanner(kind: HelpBannerKind.tools),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (q) {
              _source.setQuery(q);
              setState(() => _pageIndex = 0);
            },
            decoration: InputDecoration(
              hintText: context.t('ai_admin.search_tools_hint'),
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
                      },
                    ),
            ),
          ),
        ),
        if (_source.rowCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(context.t('ai_admin.no_tools'),
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '${_source.rowCount} ${context.t('ai_admin.tools_registered_suffix')}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          // No outer SingleChildScrollView — see comment in
          // ai_admin_screen.dart Agents tab. Wrapping PaginatedDataTable
          // in a horizontal SingleChildScrollView causes the scroll
          // gesture detector to win the gesture arena and DataCell taps
          // never fire.
          AnimatedBuilder(
            animation: _source,
            builder: (context, _) {
              _source.cellStyle = cellStyle;
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
                            label: Text(context.t('ai_admin.col_label'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_modality'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_kind'), style: headerStyle),
                            onSort: _onSort),
                        DataColumn(
                            label: Text(context.t('ai_admin.col_params'), style: headerStyle),
                            numeric: true,
                            onSort: _onSort),
                      ],
                      rows: pageRows,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _ToolsDataSource extends DataTableSource {
  _ToolsDataSource({required this.onTap});

  // Same filter+sort pattern as the Agents/Skills sources in
  // ai_admin_screen.dart — see comments there.
  final List<Map<String, dynamic>> _allRows = [];
  final List<Map<String, dynamic>> _rows = [];
  String _query = '';
  Comparable<dynamic> Function(Map<String, dynamic>)? _lastSorter;
  bool _lastAscending = true;

  TextStyle cellStyle = const TextStyle(color: AppTheme.textBright, fontSize: 13);
  final void Function(Map<String, dynamic>) onTap;

  void setRows(List<Map<String, dynamic>> rows) {
    _allRows
      ..clear()
      ..addAll(rows);
    _rebuild();
  }

  void setQuery(String q) {
    _query = q.toLowerCase().trim();
    _rebuild();
  }

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
    final schema = r['params_schema'] as Map<String, dynamic>?;
    final paramCount =
        (schema?['properties'] as Map<String, dynamic>?)?.length ?? 0;
    final desc = (r['description'] ?? '').toString();
    final tooltipMsg = desc.isEmpty ? '(no description)' : desc;
    return DataRow(
      cells: [
        DataCell(
          Tooltip(
            message: tooltipMsg,
            waitDuration: const Duration(milliseconds: 250),
            child: Text(r['name'] ?? '', style: cellStyle),
          ),
          onTap: () => onTap(r),
        ),
        DataCell(Text(r['label'] ?? '', style: cellStyle), onTap: () => onTap(r)),
        DataCell(Text(r['modality'] ?? 'any', style: cellStyle)),
        DataCell(Text(r['kind'] ?? 'python_tool', style: cellStyle)),
        DataCell(Text(paramCount == 0 ? '—' : '$paramCount', style: cellStyle)),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => _rows.length;
  @override
  int get selectedRowCount => 0;
}
