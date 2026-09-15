import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../i18n/translate_extension.dart';
import '../../services/api_client.dart';

/// Catalogue connector types that authenticate via the OAuth2 flow, mapped to
/// the /oauth2/start `connector` value.
const Map<String, String> _oauthConnector = {
  'gmail': 'google',
  'outlook': 'microsoft',
};

class IntegrationsScreen extends ConsumerStatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  ConsumerState<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends ConsumerState<IntegrationsScreen> {
  List<Map<String, dynamic>> _catalogue = [];
  List<Map<String, dynamic>> _configured = [];
  List<Map<String, dynamic>> _credentials = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final dio = ref.read(dioProvider);
    try {
      final results = await Future.wait([
        dio.get('/integrations/catalogue'),
        dio.get('/integrations'),
        dio.get('/credentials'),
      ]);
      if (!mounted) return;
      setState(() {
        _catalogue = List<Map<String, dynamic>>.from(results[0].data as List);
        _configured = List<Map<String, dynamic>>.from(results[1].data as List);
        _credentials = List<Map<String, dynamic>>.from(results[2].data as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Map<String, Map<String, dynamic>> get _byType {
    return {for (final c in _catalogue) c['type'] as String: c};
  }

  Future<void> _delete(Map<String, dynamic> integration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('integrations.delete_title')),
        content: Text(
          '${ctx.t('integrations.delete_body')} "${integration["name"]}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failMsg = context.t('common.request_failed');
    try {
      await ref.read(dioProvider).delete('/integrations/${integration["id"]}');
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$failMsg: $e')));
    }
  }

  Future<void> _add(Map<String, dynamic> connector) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddIntegrationDialog(
        connector: connector,
        credentials: _credentials,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('integrations.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final c in _catalogue) {
      byCategory.putIfAbsent(c['category'] as String? ?? 'Other', () => []).add(c);
    }
    final categories = byCategory.keys.toList()..sort();
    final byType = _byType;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.t('integrations.subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),

          // ── Your integrations ────────────────────────────────────────
          Text(
            context.t('integrations.your_integrations'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_configured.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.t('integrations.none_configured'),
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            )
          else
            ..._configured.map((i) {
              final entry = byType[i['connector_type']];
              final icon = entry?['icon'] as String? ?? '🔌';
              return Card(
                child: ListTile(
                  leading: Text(icon, style: const TextStyle(fontSize: 22)),
                  title: Text(i['name'] as String? ?? ''),
                  subtitle: Text(
                    entry?['name'] as String? ?? i['connector_type'] as String? ?? '',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i['credential_id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Badge(
                            label: context.t('integrations.credential_linked'),
                            color: Colors.green,
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(i),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 20),

          // ── Available connectors ─────────────────────────────────────
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                category.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
            for (final c in byCategory[category]!)
              Card(
                child: ListTile(
                  leading: Text(
                    c['icon'] as String? ?? '🔌',
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(c['name'] as String? ?? ''),
                  subtitle: Text(c['description'] as String? ?? ''),
                  trailing: FilledButton(
                    onPressed: () => _add(c),
                    child: Text(context.t('integrations.add')),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AddIntegrationDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> connector;
  final List<Map<String, dynamic>> credentials;

  const _AddIntegrationDialog({required this.connector, required this.credentials});

  @override
  ConsumerState<_AddIntegrationDialog> createState() => _AddIntegrationDialogState();
}

class _AddIntegrationDialogState extends ConsumerState<_AddIntegrationDialog> {
  late final TextEditingController _name;
  final List<_KvRow> _config = [_KvRow()];
  String? _credentialId;
  bool _busy = false;
  String? _oauthUrl;

  String get _type => widget.connector['type'] as String;
  String? get _oauthProvider => _oauthConnector[_type];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.connector['name'] as String? ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _config) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final config = <String, dynamic>{};
    for (final r in _config) {
      final k = r.key.text.trim();
      if (k.isNotEmpty) config[k] = r.value.text;
    }
    final messenger = ScaffoldMessenger.of(context);
    final failMsg = context.t('integrations.create_failed');
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/integrations', data: {
        'connector_type': _type,
        'name': _name.text.trim().isEmpty
            ? widget.connector['name']
            : _name.text.trim(),
        'credential_id': _credentialId,
        'config': config,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('$failMsg: $e')));
    }
  }

  Future<void> _startOauth() async {
    final messenger = ScaffoldMessenger.of(context);
    final failMsg = context.t('integrations.oauth_failed');
    setState(() {
      _busy = true;
      _oauthUrl = null;
    });
    try {
      final resp = await ref.read(dioProvider).get('/oauth2/start', queryParameters: {
        'connector': _oauthProvider,
        'name': _name.text.trim().isEmpty ? widget.connector['name'] : _name.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _oauthUrl = (resp.data as Map<String, dynamic>)['auth_url'] as String?;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('$failMsg: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${context.t('integrations.add')} ${widget.connector['name']}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: context.t('integrations.name')),
              ),
              if (widget.credentials.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _credentialId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Credential'),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.t('integrations.no_credential')),
                    ),
                    ...widget.credentials.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c['id'] as String,
                        child: Text('${c['name']} (${c['type']})'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _credentialId = v),
                ),
              ],
              if (_oauthProvider != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(context.t('integrations.authorize_oauth')),
                  onPressed: _busy ? null : _startOauth,
                ),
                if (_oauthUrl != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.t('integrations.oauth_hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(_oauthUrl!, style: const TextStyle(fontSize: 12)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _oauthUrl!)),
                      child: Text(context.t('integrations.copy_url')),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Text(
                context.t('integrations.config_optional'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final r in _config)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: r.key,
                          decoration: InputDecoration(
                            labelText: context.t('integrations.field_key'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: r.value,
                          decoration: InputDecoration(
                            labelText: context.t('integrations.field_value'),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _config.length == 1
                            ? null
                            : () => setState(() {
                                  r.dispose();
                                  _config.remove(r);
                                }),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(context.t('integrations.add_field')),
                  onPressed: () => setState(() => _config.add(_KvRow())),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(context.t('common.cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy ? context.t('integrations.saving') : context.t('integrations.save'),
          ),
        ),
      ],
    );
  }
}

class _KvRow {
  final TextEditingController key = TextEditingController();
  final TextEditingController value = TextEditingController();

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${context.t('common.error_prefix')}: $message'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text(context.t('common.retry'))),
        ],
      ),
    );
  }
}
