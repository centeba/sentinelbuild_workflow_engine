import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'ai_admin_api.dart';

/// Create / edit dialog for an ``AIAgentConfig`` row.
///
/// The skill multi-select is sourced from the live ``/ai-skills`` list so
/// every active skill (Python tool or prompt fragment) is available.
class AgentEditDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? agent;
  const AgentEditDialog({super.key, this.agent});

  @override
  ConsumerState<AgentEditDialog> createState() => _AgentEditDialogState();
}

class _AgentEditDialogState extends ConsumerState<AgentEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _label;
  late final TextEditingController _description;
  late final TextEditingController _systemPrompt;
  late final TextEditingController _modelName;
  late String _provider;
  late String _scope;
  late bool _active;
  // OpenRouter gateway policy. When the provider is 'openrouter' and this is
  // off, the backend downgrades the call to a direct vendor (privacy). Stored
  // inside model_configuration.allow_gateway; other config keys are preserved.
  late bool _allowGateway;
  // Per-agent PII masking policy override, stored in
  // model_configuration.pii_masking_policy. 'inherit' = don't set the key, so
  // the company/env default applies; an explicit value can only TIGHTEN the
  // effective policy (the firewall takes the most-restrictive of company+agent).
  late String _piiPolicy;
  static const _piiPolicies = ['inherit', 'off', 'detect-only', 'enforce', 'strict'];
  Map<String, dynamic> _modelConfig = {};

  List<Map<String, dynamic>> _skills = const [];
  late Set<String> _selectedSkillIds;
  // G7 — per-tool approval mode (skill_id → mode) for attached python_tool skills.
  final Map<String, String> _approvalModeBySkillId = {};
  static const _approvalModes = ['auto', 'allow', 'require_approval', 'deny'];
  bool _saving = false;

  // Phase G — grants for scope='shared' agents.
  List<Map<String, dynamic>> _grants = const [];

  static const _providers = ['anthropic', 'openai', 'gemini', 'openrouter'];
  static const _scopes = ['company', 'platform', 'shared'];

  @override
  void initState() {
    super.initState();
    final a = widget.agent ?? const {};
    _name = TextEditingController(text: a['name'] ?? '');
    _label = TextEditingController(text: a['label'] ?? '');
    _description = TextEditingController(text: a['description'] ?? '');
    _systemPrompt = TextEditingController(text: a['system_prompt'] ?? '');
    _modelName = TextEditingController(
        text: a['model_name'] ?? 'claude-3-5-sonnet-20240620');
    _provider = a['provider_type'] ?? 'anthropic';
    _scope = a['scope'] ?? 'company';
    _active = a['is_active'] ?? true;
    // Parse the existing model_configuration JSON (base_url, temperature, …)
    // so we preserve it on save; read the allow_gateway flag (default true).
    final rawCfg = a['model_configuration'];
    if (rawCfg is String && rawCfg.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCfg);
        if (decoded is Map) _modelConfig = Map<String, dynamic>.from(decoded);
      } catch (_) {/* malformed → start fresh */}
    } else if (rawCfg is Map) {
      _modelConfig = Map<String, dynamic>.from(rawCfg);
    }
    _allowGateway = _modelConfig['allow_gateway'] as bool? ?? true;
    final rawPii = _modelConfig['pii_masking_policy'];
    _piiPolicy = (rawPii is String && _piiPolicies.contains(rawPii)) ? rawPii : 'inherit';
    final attached = (a['skills'] as List?) ?? const [];
    _selectedSkillIds = attached.map<String>((s) => s['id'].toString()).toSet();
    final modes = (a['skill_modes'] as Map?) ?? const {};
    _approvalModeBySkillId
        .addAll(modes.map((k, v) => MapEntry(k.toString(), v.toString())));
    _loadSkills();
    if (widget.agent != null && _scope == 'shared') {
      _loadGrants();
    }
  }

  Future<void> _loadGrants() async {
    try {
      final list = await ref
          .read(aiAdminApiProvider)
          .listAgentGrants(widget.agent!['id'].toString());
      if (mounted) setState(() => _grants = list);
    } catch (_) {
      // 403 / 404 → leave _grants empty. The sub-form still renders;
      // attempts to add a grant will surface a snackbar error.
    }
  }

  Future<void> _loadSkills() async {
    try {
      final list = await ref.read(aiAdminApiProvider).listSkills();
      if (mounted) setState(() => _skills = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _description.dispose();
    _systemPrompt.dispose();
    _modelName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(aiAdminApiProvider);
      // Preserve existing model_configuration keys; stamp the gateway policy and
      // the per-agent PII policy. 'inherit' means don't set the key, so the
      // company/env default applies (an explicit value can only tighten).
      final cfg = {..._modelConfig, 'allow_gateway': _allowGateway};
      if (_piiPolicy == 'inherit') {
        cfg.remove('pii_masking_policy');
      } else {
        cfg['pii_masking_policy'] = _piiPolicy;
      }
      final body = {
        'name': _name.text.trim(),
        'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'system_prompt': _systemPrompt.text.trim().isEmpty
            ? null
            : _systemPrompt.text.trim(),
        'provider_type': _provider,
        'model_name': _modelName.text.trim(),
        'model_configuration': jsonEncode(cfg),
        'is_active': _active,
        'skill_ids': _selectedSkillIds.toList(),
        // G7 — per-tool approval mode, only for attached python_tool skills.
        'skill_modes': {
          for (final s in _skills)
            if (_selectedSkillIds.contains(s['id'].toString()) &&
                s['kind'] == 'python_tool')
              s['id'].toString(): _approvalModeBySkillId[s['id'].toString()] ??
                  'auto',
        },
        // Phase G — visibility scope. Backend enforces that
        // platform requires system_admin; here we just send what the
        // user picked and let the 403 surface as a snackbar if they
        // chose a value they're not allowed to set.
        'scope': _scope,
      };
      if (widget.agent == null) {
        await api.createAgent(body);
      } else {
        await api.updateAgent(widget.agent!['id'].toString(), body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.t('errors.save_failed_prefix')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.agent != null;
    return AlertDialog(
      title: Text(isEdit ? context.t('ai_admin.edit_agent') : context.t('ai_admin.new_agent'),
          style: const TextStyle(color: AppTheme.textBright)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.name'))),
            const SizedBox(height: 10),
            TextField(controller: _label,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.label'))),
            const SizedBox(height: 10),
            TextField(controller: _description, maxLines: 2,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.description'))),
            const SizedBox(height: 10),
            TextField(controller: _systemPrompt, maxLines: 4,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.system_prompt'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _provider,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.provider')),
                dropdownColor: AppTheme.bgRaised,
                // Provider values are wire identifiers — kept untranslated.
                items: _providers
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _provider = v!),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(controller: _modelName,
                      decoration: InputDecoration(labelText: context.t('ai_admin.field.model')))),
            ]),
            // OpenRouter gateway toggle — only relevant when routing through
            // the gateway. Off = keep this agent on a direct vendor (privacy).
            if (_provider == 'openrouter')
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _allowGateway,
                onChanged: (v) => setState(() => _allowGateway = v),
                title: Text(context.t('ai_admin.field.allow_gateway'),
                    style: const TextStyle(
                        color: AppTheme.textBright, fontSize: 13)),
                subtitle: Text(context.t('ai_admin.field.allow_gateway_hint'),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ),
            const SizedBox(height: 10),
            // Per-agent PII masking policy. 'inherit' keeps the company/env
            // default; an explicit value can only tighten. See the PII & AI
            // Compliance screen for the company-wide default.
            DropdownButtonFormField<String>(
              initialValue: _piiPolicy,
              decoration: InputDecoration(
                labelText: context.t('ai_admin.field.pii_policy'),
                helperText: context.t('ai_admin.field.pii_policy_help'),
                helperMaxLines: 2,
              ),
              dropdownColor: AppTheme.bgRaised,
              items: _piiPolicies
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(context.t('ai_admin.pii_policy.$p')),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _piiPolicy = v ?? 'inherit'),
            ),
            const SizedBox(height: 10),
            // Phase G — visibility scope selector.
            DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: InputDecoration(
                labelText: context.t('ai_admin.field.scope'),
                helperText: context.t('ai_admin.field.scope_help'),
                helperMaxLines: 2,
              ),
              dropdownColor: AppTheme.bgRaised,
              items: _scopes
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(context.t('ai_admin.scope.$s')),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _scope = v ?? 'company');
                if (_scope == 'shared' && widget.agent != null) {
                  _loadGrants();
                }
              },
            ),
            if (_scope == 'shared' && widget.agent != null) ...[
              const SizedBox(height: 14),
              _GrantsSubForm(
                agentId: widget.agent!['id'].toString(),
                grants: _grants,
                onChanged: _loadGrants,
              ),
            ],
            const SizedBox(height: 16),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(context.t('ai_admin.skills_tab'),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _skills.map((s) {
                final id = s['id'].toString();
                final on = _selectedSkillIds.contains(id);
                return FilterChip(
                  label: Text('${s['label'] ?? s['name']} · ${s['modality']}',
                      style: const TextStyle(fontSize: 12)),
                  selected: on,
                  onSelected: (sel) => setState(() {
                    sel ? _selectedSkillIds.add(id) : _selectedSkillIds.remove(id);
                  }),
                );
              }).toList(),
            ),
            // G7 — per-tool approval policy for attached python_tool skills.
            Builder(builder: (context) {
              final attachedTools = _skills.where((s) =>
                  _selectedSkillIds.contains(s['id'].toString()) &&
                  s['kind'] == 'python_tool').toList();
              if (attachedTools.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('Tool approvals',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final s in attachedTools)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                          child: Text('${s['label'] ?? s['name']}',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                        ),
                        DropdownButton<String>(
                          value: _approvalModeBySkillId[s['id'].toString()] ??
                              'auto',
                          isDense: true,
                          items: _approvalModes
                              .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m,
                                      style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (m) => setState(() =>
                              _approvalModeBySkillId[s['id'].toString()] =
                                  m ?? 'auto'),
                        ),
                      ]),
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: Text(context.t('common.active'),
                  style: const TextStyle(color: AppTheme.textSecondary)),
              onChanged: (v) => setState(() => _active = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(context.t('common.cancel'))),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? context.t('ai_admin.saving') : context.t('common.save')),
        ),
      ],
    );
  }
}


/// Phase G — inline sub-form for managing ``scope='shared'`` agent
/// grants. Only renders when the agent already exists (id is needed
/// for the grant endpoints); for new agents the user must save first
/// then re-open the dialog to add grants.
class _GrantsSubForm extends ConsumerStatefulWidget {
  final String agentId;
  final List<Map<String, dynamic>> grants;
  final Future<void> Function() onChanged;
  const _GrantsSubForm({
    required this.agentId,
    required this.grants,
    required this.onChanged,
  });

  @override
  ConsumerState<_GrantsSubForm> createState() => _GrantsSubFormState();
}

class _GrantsSubFormState extends ConsumerState<_GrantsSubForm> {
  final _granteeIdCtrl = TextEditingController();
  String _pays = 'owner';
  bool _adding = false;

  @override
  void dispose() {
    _granteeIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _addGrant() async {
    final id = _granteeIdCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref.read(aiAdminApiProvider).upsertAgentGrant(
            agentId: widget.agentId,
            granteeCompanyId: id,
            pays: _pays,
          );
      _granteeIdCtrl.clear();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${context.t('ai_admin.grants.add_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeGrant(Map<String, dynamic> g) async {
    try {
      await ref.read(aiAdminApiProvider).deleteAgentGrant(
            agentId: widget.agentId,
            granteeCompanyId: g['grantee_company_id'].toString(),
          );
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${context.t('ai_admin.grants.delete_failed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('ai_admin.grants.title'),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            context.t('ai_admin.grants.description'),
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textMuted, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (widget.grants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                context.t('ai_admin.grants.empty'),
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textMuted),
              ),
            )
          else
            Column(
              children: widget.grants.map((g) {
                final pays = (g['pays'] ?? 'owner').toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        g['grantee_company_id'].toString(),
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppTheme.textPrimary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${context.t('ai_admin.grants.pays')}: $pays',
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textSecondary),
                      ),
                    ),
                    IconButton(
                      tooltip: context.t('common.delete'),
                      icon: const Icon(Icons.close,
                          size: 14, color: AppTheme.textSecondary),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeGrant(g),
                    ),
                  ]),
                );
              }).toList(),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _granteeIdCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.t('ai_admin.grants.grantee_hint'),
                  hintStyle: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11),
                ),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _pays,
              isDense: true,
              dropdownColor: AppTheme.bgRaised,
              items: const [
                DropdownMenuItem(value: 'owner', child: Text('owner pays')),
                DropdownMenuItem(
                    value: 'grantee', child: Text('grantee pays')),
              ],
              onChanged: (v) => setState(() => _pays = v ?? 'owner'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _adding ? null : _addGrant,
              child: Text(context.t('common.add')),
            ),
          ]),
        ],
      ),
    );
  }
}
