import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../screens/ai_admin/ai_admin_api.dart';

/// Phase H — agentic NL search bar (mit_stack twin).
///
/// Reuses ``aiAdminDioProvider`` because that's the existing Dio
/// client wired to ``/api/integration-hub/v1`` — the same prefix
/// that hosts ``/ai-search/{entity}``.
class AiSearchBar extends ConsumerStatefulWidget {
  final String entity;
  final ValueChanged<List<Map<String, dynamic>>> onResults;
  final VoidCallback onClear;
  final String? hintText;

  const AiSearchBar({
    super.key,
    required this.entity,
    required this.onResults,
    required this.onClear,
    this.hintText,
  });

  @override
  ConsumerState<AiSearchBar> createState() => _AiSearchBarState();
}

class _AiSearchBarState extends ConsumerState<AiSearchBar> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  String? _lastSql;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _error = null;
        _lastSql = null;
      });
      widget.onClear();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(aiAdminDioProvider);
      final res = await dio.post(
        '/ai-search/${widget.entity}',
        data: {'query': query, 'limit': 100},
      );
      final rows = (res.data?['rows'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      setState(() {
        _lastSql = res.data?['sql'] as String?;
        _loading = false;
      });
      widget.onResults(rows);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['detail']?.toString() ?? '${e.message}')
          : '${e.message}';
      setState(() {
        _loading = false;
        _error = msg;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _error = null;
        _lastSql = null;
      });
      widget.onClear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), _run);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(
                  _loading ? LucideIcons.loader : LucideIcons.sparkles,
                  size: 16,
                  color: cs.primary,
                ),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(LucideIcons.x, size: 14),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
                hintText: widget.hintText ??
                    'Ask in plain English — e.g. "${_examplePlaceholder(widget.entity)}"',
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outline),
                ),
              ),
            ),
          ),
          if (_lastSql != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Generated SQL:\n$_lastSql',
              waitDuration: const Duration(milliseconds: 200),
              child: Icon(LucideIcons.info, size: 14, color: cs.onSurfaceVariant),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: _error!,
              child: Icon(LucideIcons.alertCircle, size: 14, color: cs.error),
            ),
          ],
        ],
      ),
    );
  }

  String _examplePlaceholder(String entity) {
    switch (entity) {
      case 'workflows':
        return 'active workflows triggered by webhooks';
      case 'rules':
        return 'rules with priority below 5';
      case 'forms':
        return 'public forms updated this month';
      default:
        return 'find $entity matching ...';
    }
  }
}
