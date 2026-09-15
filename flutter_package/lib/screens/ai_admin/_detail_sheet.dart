import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';

/// Which kind of object the sheet is rendering. Drives the
/// "how to use" copy and which sub-sections are visible.
enum DetailKind {
  agent,
  skillPrompt,
  skillPythonTool,
  tool,
}

/// Shared bottom-sheet used by all three AI Admin tabs (Agents,
/// Skills, Tools). Sections rendered:
///
/// 1. Header — label + monospaced name + metadata chips.
/// 2. Description — full text from ``row['description']`` or a
///    muted "no description set" fallback.
/// 3. How to use — kind-specific instructions with code snippets
///    that have a "Copy" button each.
/// 4. Parameters — the JSONSchema field list. Only rendered when
///    a non-empty ``params_schema`` is supplied (tools and
///    python_tool skills that resolve to a registered tool).
/// 5. Skills (agents only) — the labels of attached skills.
class DetailSheet extends StatelessWidget {
  const DetailSheet({
    super.key,
    required this.kind,
    required this.row,
    this.paramsSchema,
    this.attachedSkills,
  });

  final DetailKind kind;
  final Map<String, dynamic> row;

  /// JSONSchema to render under "Parameters". Optional.
  final Map<String, dynamic>? paramsSchema;

  /// Skill rows attached to this agent (only relevant when
  /// ``kind == DetailKind.agent``). Each entry is a row map with
  /// ``label``/``name``/``modality``/``kind`` etc.
  final List<Map<String, dynamic>>? attachedSkills;

  @override
  Widget build(BuildContext context) {
    final props = (paramsSchema?['properties'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final required =
        ((paramsSchema?['required'] as List?) ?? const []).cast<String>().toSet();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _Header(row: row, kind: kind),
            const SizedBox(height: 16),
            _DescriptionSection(row: row),
            const SizedBox(height: 20),
            _HowToUseSection(row: row, kind: kind),
            if (attachedSkills != null && attachedSkills!.isNotEmpty) ...[
              const SizedBox(height: 20),
              _AttachedSkillsSection(skills: attachedSkills!),
            ],
            if (props.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(context.t('ai_admin.detail.parameters'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textBright)),
              const SizedBox(height: 8),
              ...props.entries.map((e) => ParamRow(
                    name: e.key,
                    schema: Map<String, dynamic>.from(e.value as Map),
                    required: required.contains(e.key),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.row, required this.kind});
  final Map<String, dynamic> row;
  final DetailKind kind;

  @override
  Widget build(BuildContext context) {
    final label = row['label'] ?? row['name'] ?? '';
    final name = row['name'] ?? '';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textBright)),
              const SizedBox(height: 2),
              Text(name,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: _chipsFor(row, kind)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  List<Widget> _chipsFor(Map<String, dynamic> row, DetailKind kind) {
    final chips = <Widget>[];
    void add(String s) => chips.add(Chip2(label: s));
    switch (kind) {
      case DetailKind.agent:
        add('provider: ${row['provider_type'] ?? '?'}');
        add('model: ${row['model_name'] ?? '?'}');
        add(row['is_active'] == false ? 'inactive' : 'active');
        break;
      case DetailKind.skillPrompt:
        add('modality: ${row['modality'] ?? 'any'}');
        add('kind: prompt');
        add(row['is_active'] == false ? 'inactive' : 'active');
        break;
      case DetailKind.skillPythonTool:
        add('modality: ${row['modality'] ?? 'any'}');
        add('kind: python_tool');
        add(row['is_active'] == false ? 'inactive' : 'active');
        break;
      case DetailKind.tool:
        add('modality: ${row['modality'] ?? 'any'}');
        add('kind: ${row['kind'] ?? 'python_tool'}');
        break;
    }
    return chips;
  }
}

class _DescriptionSection extends StatelessWidget {
  const _DescriptionSection({required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final desc = (row['description'] ?? '').toString();
    if (desc.isEmpty) {
      return Text(
        context.t('ai_admin.detail.no_description'),
        style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            fontStyle: FontStyle.italic),
      );
    }
    return Text(desc,
        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary));
  }
}

class _HowToUseSection extends StatelessWidget {
  const _HowToUseSection({required this.row, required this.kind});
  final Map<String, dynamic> row;
  final DetailKind kind;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('ai_admin.detail.how_to_use'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textBright)),
        const SizedBox(height: 8),
        ..._bodyFor(context),
      ],
    );
  }

  List<Widget> _bodyFor(BuildContext context) {
    switch (kind) {
      case DetailKind.agent:
        final id = row['id']?.toString() ?? '<agent-id>';
        return [
          _Para(context.t('ai_admin.detail.agent_reference_intro')),
          _CodeBlock(
            text:
                '{\n  "type": "agent_node",\n  "config": {"agent_id": "$id"}\n}',
          ),
          const SizedBox(height: 8),
          _Para(context.t('ai_admin.detail.or_invoke_directly')),
          _CodeBlock(
            text:
                'curl -X POST /api/integration-hub/v1/ai-agents/$id/run \\\n  -H "Authorization: Bearer <token>" \\\n  -d \'{"input": "..."}\'',
          ),
        ];
      case DetailKind.skillPrompt:
        return [
          _Para(context.t('ai_admin.detail.skill_prompt_help')),
        ];
      case DetailKind.skillPythonTool:
        final regName = (row['content'] ?? row['name'] ?? '<tool-name>').toString();
        return [
          // ``regName`` is interpolated into the localized template via
          // a placeholder marker so translators see one placeholder.
          _Para(
              '${context.t('ai_admin.detail.skill_python_help_prefix')} `$regName`. '
              '${context.t('ai_admin.detail.skill_python_help_suffix')}'),
          _CodeBlock(
            text:
                'curl -X POST /api/integration-hub/v1/ai-tools/run \\\n  -H "Authorization: Bearer <token>" \\\n  -d \'{"skill_name": "$regName", "args": {...}}\'',
          ),
        ];
      case DetailKind.tool:
        final name = row['name']?.toString() ?? '<tool-name>';
        return [
          _Para(context.t('ai_admin.detail.tool_help_intro')),
          _CodeBlock(
            text:
                '{\n  "type": "action_node",\n  "config": {"skill_name": "$name", "args": {}}\n}',
          ),
          const SizedBox(height: 8),
          _Para(context.t('ai_admin.detail.or_invoke_dispatch')),
          _CodeBlock(
            text:
                'curl -X POST /api/integration-hub/v1/ai-tools/run \\\n  -H "Authorization: Bearer <token>" \\\n  -d \'{"skill_name": "$name", "args": {...}}\'',
          ),
        ];
    }
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
      );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.bgRaised),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textBright,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            tooltip: context.t('common.copy'),
            icon: const Icon(Icons.copy, size: 14, color: AppTheme.textSecondary),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              // Capture localized copy snackbar BEFORE the await.
              final tCopied = context.t('ai_admin.detail.copied_to_clipboard');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tCopied),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AttachedSkillsSection extends StatelessWidget {
  const _AttachedSkillsSection({required this.skills});
  final List<Map<String, dynamic>> skills;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${context.t('ai_admin.detail.attached_skills')} (${skills.length})',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textBright)),
        const SizedBox(height: 8),
        ...skills.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(
                  width: 220,
                  child: Text(
                    s['label'] ?? s['name'] ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textBright),
                  ),
                ),
                const SizedBox(width: 8),
                Text(s['kind'] ?? 'prompt',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(width: 8),
                Text('· ${s['modality'] ?? 'any'}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
              ]),
            )),
      ],
    );
  }
}

/// Public chip used by the header. Exported (no leading underscore)
/// so the callers can build their own header chips if they need to,
/// but the standard usage is the auto-generated set above.
class Chip2 extends StatelessWidget {
  const Chip2({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgPage,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      );
}

/// One row in the Parameters section. Long descriptions wrap to a
/// second line via ``Wrap`` rather than getting eaten by the
/// expanding text column.
class ParamRow extends StatelessWidget {
  const ParamRow({
    super.key,
    required this.name,
    required this.schema,
    required this.required,
  });

  final String name;
  final Map<String, dynamic> schema;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final type = (schema['type'] ?? 'any').toString();
    final fmt = schema['format'];
    final enumVals = schema['enum'];
    String typeLabel = type;
    if (fmt != null) typeLabel = '$type ($fmt)';
    if (enumVals is List) typeLabel = 'enum [${enumVals.join(', ')}]';
    final desc = (schema['description'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: AppTheme.textBright)),
              ),
              if (required)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('*',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFFFCA5A5))),
                ),
              const SizedBox(width: 12),
              Text(typeLabel,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text(desc,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textMuted)),
            ),
        ],
      ),
    );
  }
}
