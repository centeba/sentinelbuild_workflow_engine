import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'ai_admin_api.dart';

/// Create / edit dialog for a single ``AISkill`` row.
///
/// ``kind=prompt`` → free-text content editor (becomes a system-prompt
/// fragment at runtime). ``kind=python_tool`` → the ``content`` field
/// is the registry name; the dropdown is populated from
/// ``GET /ai-skills/registry`` so the user can't typo a missing tool.
class SkillEditDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? skill;
  const SkillEditDialog({super.key, this.skill});

  @override
  ConsumerState<SkillEditDialog> createState() => _SkillEditDialogState();
}

class _SkillEditDialogState extends ConsumerState<SkillEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _label;
  late final TextEditingController _description;
  late final TextEditingController _content;
  late String _kind;
  late String _modality;
  late bool _active;
  late bool _agentOnly;

  List<Map<String, dynamic>> _registry = const [];
  bool _saving = false;

  static const _kinds = ['prompt', 'python_tool'];
  static const _modalities = ['any', 'document', 'image', 'video', 'audio', 'text'];

  @override
  void initState() {
    super.initState();
    final s = widget.skill ?? const {};
    _name = TextEditingController(text: s['name'] ?? '');
    _label = TextEditingController(text: s['label'] ?? '');
    _description = TextEditingController(text: s['description'] ?? '');
    _content = TextEditingController(text: s['content'] ?? '');
    _kind = s['kind'] ?? 'prompt';
    _modality = s['modality'] ?? 'any';
    _active = s['is_active'] ?? true;
    _agentOnly = s['agent_only'] ?? false;
    _loadRegistry();
  }

  Future<void> _loadRegistry() async {
    try {
      final reg = await ref.read(aiAdminApiProvider).listRegistry();
      if (mounted) setState(() => _registry = reg);
    } catch (_) {/* registry endpoint optional */}
  }

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _description.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(aiAdminApiProvider);
      final body = {
        'name': _name.text.trim(),
        'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'kind': _kind,
        'modality': _modality,
        'content': _content.text.trim().isEmpty ? null : _content.text.trim(),
        'is_active': _active,
        'agent_only': _agentOnly,
      };
      if (widget.skill == null) {
        await api.createSkill(body);
      } else {
        await api.updateSkill(widget.skill!['id'].toString(), body);
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
    final isEdit = widget.skill != null;
    return AlertDialog(
      title: Text(isEdit ? context.t('ai_admin.edit_skill') : context.t('ai_admin.new_skill'),
          style: const TextStyle(color: AppTheme.textBright)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.name'))),
            const SizedBox(height: 10),
            TextField(controller: _label,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.label_ui'))),
            const SizedBox(height: 10),
            TextField(controller: _description, maxLines: 2,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.description'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.kind')),
                dropdownColor: AppTheme.bgRaised,
                // Kind values are wire identifiers — kept untranslated.
                items: _kinds.map((k) =>
                    DropdownMenuItem(value: k, child: Text(k))).toList(),
                onChanged: (v) => setState(() => _kind = v!),
              )),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _modality,
                decoration: InputDecoration(labelText: context.t('ai_admin.field.modality')),
                dropdownColor: AppTheme.bgRaised,
                items: _modalities.map((m) =>
                    DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _modality = v!),
              )),
            ]),
            const SizedBox(height: 10),
            if (_kind == 'python_tool')
              DropdownButtonFormField<String>(
                initialValue: _registry.any((r) => r['name'] == _content.text)
                    ? _content.text
                    : (_registry.isNotEmpty ? _registry.first['name'] as String : null),
                decoration: InputDecoration(labelText: context.t('ai_admin.field.registry_tool')),
                dropdownColor: AppTheme.bgRaised,
                items: _registry
                    .map((r) => DropdownMenuItem(
                          value: r['name'] as String,
                          child: Text('${r['label'] ?? r['name']} (${r['modality']})'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _content.text = v ?? ''),
              )
            else
              TextField(
                controller: _content,
                maxLines: 6,
                decoration: InputDecoration(
                    labelText: context.t('ai_admin.field.prompt_content'),
                    hintText: context.t('ai_admin.field.prompt_content_hint')),
              ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: Text(context.t('common.active'),
                  style: const TextStyle(color: AppTheme.textSecondary)),
              onChanged: (v) => setState(() => _active = v),
            ),
            // Only meaningful for python_tool skills — prompt skills are
            // inherently agent-only and never appear in the builder palette.
            if (_kind == 'python_tool')
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _agentOnly,
                title: const Text('Agent-only',
                    style: TextStyle(color: AppTheme.textSecondary)),
                subtitle: const Text(
                  'Hide from the workflow builder palette; usable only inside '
                  'an agent\'s attached skills.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                onChanged: (v) => setState(() => _agentOnly = v),
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
