// Phase G — Platform LLM keys sub-tab.
//
// System-admin-only surface. Manages rows in ``platform_llm_api_keys``
// — the credentials that bill calls through ``scope='platform'``
// agents.
//
// Auth gating: the backend's ``PlatformAdminDep`` returns 403 for
// non-admins, which we surface as a clean empty-state message rather
// than hiding the tab entirely (mit_stack has no host-injected role
// provider). When 403 comes back the rest of the tab is harmless —
// the inputs do nothing useful for a non-admin.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'ai_admin_api.dart';

class PlatformKeysTab extends ConsumerStatefulWidget {
  const PlatformKeysTab({super.key});

  @override
  ConsumerState<PlatformKeysTab> createState() => _PlatformKeysTabState();
}

class _PlatformKeysTabState extends ConsumerState<PlatformKeysTab> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;
  String? _error;
  // ``_forbidden`` is the soft fallback when the backend returns 403
  // (caller isn't platform_admin). Render a friendly "you don't have
  // access" panel instead of leaving the user staring at a bare
  // error.
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    try {
      final rows = await ref.read(aiAdminApiProvider).listPlatformKeys();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _loading = false;
        _forbidden = msg.contains('403');
        _error = _forbidden ? null : msg;
      });
    }
  }

  Future<void> _createKey() async {
    final provider = TextEditingController();
    final apiKey = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: Text(ctx.t('ai_admin.platform_keys.new_title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: 'anthropic',
                decoration: const InputDecoration(labelText: 'Provider'),
                items: const [
                  DropdownMenuItem(value: 'anthropic', child: Text('anthropic')),
                  DropdownMenuItem(value: 'openai', child: Text('openai')),
                  DropdownMenuItem(value: 'gemini', child: Text('gemini')),
                ],
                onChanged: (v) => provider.text = v ?? 'anthropic',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKey,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.t('common.save'))),
        ],
      ),
    );
    if (ok != true) return;
    final p = provider.text.isNotEmpty ? provider.text : 'anthropic';
    if (apiKey.text.trim().isEmpty) return;
    try {
      await ref
          .read(aiAdminApiProvider)
          .createPlatformKey(provider: p, apiKey: apiKey.text.trim());
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${context.t('ai_admin.platform_keys.create_failed')}: $e')));
    }
  }

  Future<void> _deleteKey(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: Text(ctx.t('ai_admin.platform_keys.delete_title')),
        content: Text(
            '${ctx.t('ai_admin.platform_keys.delete_prefix')} "${row['provider']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.t('common.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(aiAdminApiProvider).deletePlatformKey(row['id'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_forbidden) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  size: 32, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(
                context.t('ai_admin.platform_keys.forbidden'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Text('Error: $_error',
            style: const TextStyle(color: AppTheme.errorText)),
      );
    }
    final rows = _rows ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.t('ai_admin.platform_keys.title'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textBright),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 14),
                label: Text(context.t('ai_admin.platform_keys.add_key')),
                onPressed: _createKey,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            context.t('ai_admin.platform_keys.description'),
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                context.t('ai_admin.platform_keys.empty'),
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = rows[i];
                final active = r['is_active'] == true;
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    border: Border.all(color: AppTheme.borderSubtle),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        active ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: active
                            ? AppTheme.successText
                            : AppTheme.errorText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r['provider'].toString(),
                          style: const TextStyle(
                              color: AppTheme.textBright,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        tooltip: context.t('common.delete'),
                        icon: const Icon(Icons.delete_outline,
                            size: 16, color: AppTheme.textSecondary),
                        onPressed: () => _deleteKey(r),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
