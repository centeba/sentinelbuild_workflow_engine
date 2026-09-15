import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'ai_admin_api.dart';

/// Phase-E4 Usage tab — bar chart of spend by agent + budget editor.
///
/// Charting kept dependency-free (a hand-rolled horizontal bar grid)
/// so we don't pull in fl_chart purely for the admin page; the data
/// shape from ``GET /ai-usage/`` is small (≤ N agents per company).
class UsageTab extends ConsumerStatefulWidget {
  const UsageTab({super.key});

  @override
  ConsumerState<UsageTab> createState() => _UsageTabState();
}

class _UsageTabState extends ConsumerState<UsageTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  final _budgetCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _budgetCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref.read(aiAdminApiProvider).getUsage();
      if (!mounted) return;
      setState(() {
        _data = d;
        _budgetCtl.text =
            ((d['monthly_budget_usd'] ?? 0) as num).toStringAsFixed(2);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveBudget() async {
    final value = double.tryParse(_budgetCtl.text.trim());
    if (value == null || value < 0) return;
    try {
      await ref.read(aiAdminApiProvider).setBudget(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Budget set to \$${value.toStringAsFixed(2)}')),
        );
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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

    final events = List<Map<String, dynamic>>.from(_data?['events'] ?? []);
    final totalIn = events.fold<int>(
        0, (s, e) => s + ((e['input_tokens'] ?? 0) as num).toInt());
    final totalOut = events.fold<int>(
        0, (s, e) => s + ((e['output_tokens'] ?? 0) as num).toInt());
    final byAgent = List<Map<String, dynamic>>.from(_data?['by_agent'] ?? []);
    final totalSpend = byAgent.fold<double>(
      0,
      (s, r) => s + ((r['usd_cost'] ?? 0) as num).toDouble(),
    );
    final maxBar = byAgent.fold<double>(
      0.01,
      (m, r) => ((r['usd_cost'] ?? 0) as num).toDouble() > m
          ? ((r['usd_cost'] ?? 0) as num).toDouble()
          : m,
    );
    final budget = ((_data?['monthly_budget_usd'] ?? 0) as num).toDouble();
    final pct = budget > 0 ? (totalSpend / budget).clamp(0.0, 1.0) : 0.0;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Budget editor ────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('usage.monthly_budget_title'),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textBright)),
              const SizedBox(height: 4),
              Text(context.t('usage.monthly_budget_explanation'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _budgetCtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      labelText: context.t('usage.usd_per_month'),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _saveBudget, child: Text(context.t('common.save'))),
              ]),
              const SizedBox(height: 12),
              if (budget > 0) ...[
                LinearProgressIndicator(
                  value: pct,
                  color: pct >= 1.0
                      ? Colors.red
                      : (pct >= 0.8 ? Colors.orange : Colors.green),
                ),
                const SizedBox(height: 4),
                Text(
                  '${context.t('usage.spent_label')} \$${totalSpend.toStringAsFixed(2)} '
                  '${context.t('usage.of_label')} \$${budget.toStringAsFixed(2)} '
                  '(${(pct * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // ── Spend by agent ─────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('usage.spend_by_agent_title'),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textBright)),
              const SizedBox(height: 12),
              if (byAgent.isEmpty)
                Text(context.t('usage.no_events'),
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))
              else
                ...byAgent.map((row) {
                  final cost = ((row['usd_cost'] ?? 0) as num).toDouble();
                  final agentId = row['agent_id'] ?? 'unattributed';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                        width: 220,
                        child: Text(agentId.toString(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textBright)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: cost / maxBar,
                            minHeight: 14,
                            backgroundColor: Colors.grey.shade200,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: Text('\$${cost.toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textBright)),
                      ),
                    ]),
                  );
                }),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // ── Usage details (per-call table) ─────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Usage details',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppTheme.textBright)),
              const SizedBox(height: 4),
              Text(
                '${events.length} call(s)  ·  '
                '${_fmtInt(totalIn)} in / ${_fmtInt(totalOut)} out tokens  ·  '
                '\$${totalSpend.toStringAsFixed(4)} total',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              if (events.isEmpty)
                Text(context.t('usage.no_events'),
                    style:
                        const TextStyle(color: AppTheme.textMuted, fontSize: 12))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(
                        color: AppTheme.borderStrong, width: 1),
                    headingRowColor: const WidgetStatePropertyAll(
                        AppTheme.bgRaised),
                    headingRowHeight: 36,
                    dataRowMinHeight: 34,
                    dataRowMaxHeight: 44,
                    columnSpacing: 24,
                    headingTextStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textBright),
                    dataTextStyle: const TextStyle(
                        fontSize: 12, color: AppTheme.textBright),
                    columns: const [
                      DataColumn(label: Text('When')),
                      DataColumn(label: Text('Provider')),
                      DataColumn(label: Text('Model')),
                      DataColumn(label: Text('Input'), numeric: true),
                      DataColumn(label: Text('Output'), numeric: true),
                      DataColumn(label: Text('Cost (USD)'), numeric: true),
                    ],
                    rows: events.map((e) {
                      final cost = ((e['usd_cost'] ?? 0) as num).toDouble();
                      return DataRow(cells: [
                        DataCell(Text(_fmtTime(e['created_at']))),
                        DataCell(Text((e['provider'] ?? '—').toString())),
                        DataCell(Text((e['model'] ?? '—').toString())),
                        DataCell(Text(
                            _fmtInt((e['input_tokens'] ?? 0) as num))),
                        DataCell(Text(
                            _fmtInt((e['output_tokens'] ?? 0) as num))),
                        DataCell(Text('\$${cost.toStringAsFixed(6)}')),
                      ]);
                    }).toList(),
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  /// Thousands-separated integer (no intl dependency).
  static String _fmtInt(num n) {
    final s = n.toInt().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Compact local timestamp `MM-DD HH:MM` from an ISO-8601 string.
  static String _fmtTime(dynamic iso) {
    final dt = DateTime.tryParse(iso?.toString() ?? '');
    if (dt == null) return '—';
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
