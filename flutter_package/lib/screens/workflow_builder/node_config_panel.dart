import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workflow_node.dart';
import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'agent_node_config.dart';
import 'node_type_registry.dart';
import 'schema_condition_builder.dart';
import 'schema_driven_config_form.dart';
import 'tool_params_form.dart';

class NodeConfigPanel extends ConsumerStatefulWidget {
  final WorkflowNode node;
  final void Function(Map<String, dynamic> config) onConfigChanged;
  final VoidCallback onClose;
  const NodeConfigPanel({super.key, required this.node, required this.onConfigChanged, required this.onClose});
  @override
  ConsumerState<NodeConfigPanel> createState() => _NodeConfigPanelState();
}

class _NodeConfigPanelState extends ConsumerState<NodeConfigPanel> {
  late Map<String, TextEditingController> _controllers;
  List<_FieldDef> get _fields => _fieldsFor(widget.node.type);

  @override
  void initState() { super.initState(); _initControllers(); }

  @override
  void didUpdateWidget(NodeConfigPanel old) {
    super.didUpdateWidget(old);
    if (old.node.id != widget.node.id || old.node.type != widget.node.type) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _controllers = {
      for (final f in _fields)
        f.key: TextEditingController(text: widget.node.config[f.key]?.toString() ?? ''),
    };
    for (final ctrl in _controllers.values) ctrl.addListener(_emit);
  }

  void _disposeControllers() { for (final c in _controllers.values) c.dispose(); }
  void _emit() { widget.onConfigChanged({for (final f in _fields) f.key: _controllers[f.key]!.text}); }

  @override
  void dispose() { _disposeControllers(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: AppTheme.bgSurface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(children: [
            Expanded(child: Text(
              widget.node.type.replaceAll('_', ' ').toUpperCase(),
              style: AppTheme.sectionLabel,
            )),
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final field in _fields) ...[
                // Hide the bare ``agent_id`` text field for
                // ``agent_node`` — the AgentNodeConfig dropdown below
                // owns the same controller and offers a friendlier
                // picker. Other node types still render it normally.
                if (!(widget.node.type == 'agent_node' && field.key == 'agent_id')) ...[
                  _ConfigField(field: field, controller: _controllers[field.key]!),
                  const SizedBox(height: 12),
                ],
              ],
              // ``agent_node`` — replace the bare agent_id text field
              // with the richer dropdown + skill chips form. The
              // surrounding ``input`` field still comes from the
              // standard _fields path above.
              if (widget.node.type == 'agent_node') ...[
                AgentNodeConfig(
                  agentId: _controllers['agent_id']?.text ?? '',
                  onAgentSelected: (id) {
                    final ctl = _controllers['agent_id'];
                    if (ctl != null && ctl.text != id) {
                      ctl.text = id;
                      // _emit fires via the controller listener.
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              // Phase E1 — for tool nodes, append a schema-driven form
              // for the registered skill's params. Ignored for any
              // other node type.
              if (widget.node.type == 'tool_node')
                ToolParamsForm(
                  skillName: (widget.node.config['skill_name'] ?? '').toString(),
                  initialValues: Map<String, dynamic>.from(widget.node.config),
                  onChanged: (values) {
                    final merged = {
                      for (final f in _fields) f.key: _controllers[f.key]!.text,
                      ...values,
                    };
                    widget.onConfigChanged(merged);
                  },
                ),
              // Pack-contributed nodes (`pack_trigger` / `pack_action`)
              // — render the JSON Schema attached to their registry
              // entry. The admin sees pickers + typed fields specific
              // to the pack's domain (e.g. "Role ▾", "Email template
              // ▾") and never types JSONPath or URLs.
              if (widget.node.type == 'pack_trigger' ||
                  widget.node.type == 'pack_action')
                _PackNodeConfigBody(
                  node: widget.node,
                  onConfigChanged: widget.onConfigChanged,
                ),
              // domain_condition — a no-code branch on live domain data.
              // The user picks domain→field→value via SchemaConditionBuilder;
              // the executor fetches the entities and routes true/false.
              if (widget.node.type == 'domain_condition')
                _DomainConditionConfig(
                  node: widget.node,
                  onConfigChanged: widget.onConfigChanged,
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Looks up the pack node's spec in the node-type registry and
/// renders its config schema via [SchemaDrivenConfigForm]. Kept
/// as a separate ConsumerWidget so the registry fetch happens
/// lazily, only when a pack node is actually selected.
class _PackNodeConfigBody extends ConsumerWidget {
  final WorkflowNode node;
  final void Function(Map<String, dynamic>) onConfigChanged;

  const _PackNodeConfigBody({
    required this.node,
    required this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeKey = (node.config['node_key'] ?? '').toString();
    if (nodeKey.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Pack node has no node_key — palette item is misconfigured.',
          style: TextStyle(fontSize: 11, color: AppTheme.error),
        ),
      );
    }

    final async = ref.watch(nodeTypeRegistryProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Schema unavailable: $e',
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ),
      data: (registry) {
        final spec = registry.lookup(nodeKey);
        if (spec == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Unknown node key: $nodeKey',
              style: const TextStyle(fontSize: 11, color: AppTheme.error),
            ),
          );
        }
        // Triggers carry a `filter_schema`; actions a `config_schema`.
        // Whichever is non-empty becomes the form schema.
        final schema = (spec['config_schema'] as Map?)?.cast<String, dynamic>() ??
            (spec['filter_schema'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final isTrigger = registry.packTriggers.any((t) => t['key'] == nodeKey);
        final form = SchemaDrivenConfigForm(
          schema: schema,
          initialValues: Map<String, dynamic>.from(node.config),
          onChanged: (values) {
            onConfigChanged({
              ...node.config,
              ...values,
            });
          },
        );
        if (!isTrigger) return form;
        // Pack triggers also get a no-code domain condition builder: "only run
        // when these conditions match", evaluated against the event payload.
        final conditions =
            (node.config['conditions'] as Map?)?.cast<String, dynamic>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            form,
            const SizedBox(height: 12),
            Text(
              'ONLY RUN WHEN',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 0.4, color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            SchemaConditionBuilder(
              domains: registry.packDataDomains,
              value: conditions,
              onChanged: (group) {
                onConfigChanged({
                  ...node.config,
                  'conditions': group,
                });
              },
            ),
          ],
        );
      },
    );
  }
}

/// Config body for the built-in ``domain_condition`` branch node: a project
/// binding + the no-code SchemaConditionBuilder. Routes true_branch/false_branch
/// at run time based on live domain data.
class _DomainConditionConfig extends ConsumerWidget {
  final WorkflowNode node;
  final void Function(Map<String, dynamic>) onConfigChanged;

  const _DomainConditionConfig({
    required this.node,
    required this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nodeTypeRegistryProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('Schema unavailable: $e',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ),
      data: (registry) {
        final projectId =
            (node.config['project_id'] ?? '{{trigger.project_id}}').toString();
        final conditions =
            (node.config['conditions'] as Map?)?.cast<String, dynamic>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: projectId,
              decoration: const InputDecoration(
                labelText: 'Project',
                helperText: 'Bind to the trigger, e.g. {{trigger.project_id}}',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => onConfigChanged({...node.config, 'project_id': v}),
            ),
            const SizedBox(height: 12),
            Text('BRANCH WHEN',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 0.4, color: AppTheme.textMuted,
                )),
            const SizedBox(height: 6),
            SchemaConditionBuilder(
              domains: registry.packDataDomains,
              value: conditions,
              onChanged: (group) =>
                  onConfigChanged({...node.config, 'conditions': group}),
            ),
          ],
        );
      },
    );
  }
}

class _ConfigField extends StatelessWidget {
  final _FieldDef field;
  final TextEditingController controller;
  const _ConfigField({required this.field, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.t(field.label), style: AppTheme.labelStyle),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        maxLines: field.multiline ? 4 : 1,
        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: field.hint == null ? null : context.t(field.hint!),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
      ),
      if (field.description != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(context.t(field.description!), style: AppTheme.captionStyle),
        ),
    ]);
  }
}

class _FieldDef {
  final String key;
  final String label;
  final String? hint;
  final String? description;
  final bool multiline;
  const _FieldDef(this.key, this.label, {this.hint, this.description, this.multiline = false});
}

List<_FieldDef> _fieldsFor(String type) {
  switch (type) {
    // Pack-contributed nodes carry only `node_key` as a top-level
    // config field — everything else is rendered from the JSON Schema
    // via _PackNodeConfigBody below. The hidden node_key sticks to
    // the standard text-field path so it round-trips through save.
    case 'pack_trigger':
    case 'pack_action':
      return const [];
    case 'form_trigger':
      return [
        _FieldDef('form_slug', 'node_config.form_trigger.form_slug.label', hint: 'node_config.form_trigger.form_slug.hint', description: 'node_config.form_trigger.form_slug.description'),
        _FieldDef('form_id', 'node_config.form_trigger.form_id.label', description: 'node_config.form_trigger.form_id.description'),
      ];
    case 'webhook_trigger':
      return [_FieldDef('path', 'node_config.webhook_trigger.path.label', hint: 'node_config.webhook_trigger.path.hint'), _FieldDef('method', 'node_config.webhook_trigger.method.label', hint: 'node_config.webhook_trigger.method.hint')];
    case 'cron_trigger':
      return [_FieldDef('cron', 'node_config.cron_trigger.cron.label', hint: 'node_config.cron_trigger.cron.hint', description: 'node_config.cron_trigger.cron.description')];
    case 'http_request':
      return [_FieldDef('url', 'node_config.http_request.url.label', hint: 'node_config.http_request.url.hint'), _FieldDef('method', 'node_config.http_request.method.label', hint: 'node_config.http_request.method.hint'),
          _FieldDef('body', 'node_config.http_request.body.label', multiline: true), _FieldDef('credential_id', 'node_config.http_request.credential_id.label'),
          _FieldDef('timeout_minutes', 'node_config.http_request.timeout_minutes.label', hint: 'node_config.http_request.timeout_minutes.hint'),
          _FieldDef('continue_on_error', 'node_config.http_request.continue_on_error.label', hint: 'node_config.http_request.continue_on_error.hint', description: 'node_config.http_request.continue_on_error.description')];
    case 'web_scraper':
      return [_FieldDef('url', 'node_config.web_scraper.url.label', hint: 'node_config.web_scraper.url.hint'), _FieldDef('session_id', 'node_config.web_scraper.session_id.label'),
          _FieldDef('selectors', 'node_config.web_scraper.selectors.label', description: 'node_config.web_scraper.selectors.description', multiline: true),
          _FieldDef('continue_on_error', 'node_config.web_scraper.continue_on_error.label', hint: 'node_config.web_scraper.continue_on_error.hint')];
    case 'transform':
      return [_FieldDef('expression', 'node_config.transform.expression.label', hint: 'node_config.transform.expression.hint', multiline: true),
          _FieldDef('engine', 'node_config.transform.engine.label', hint: 'node_config.transform.engine.hint', description: 'node_config.transform.engine.description')];
    case 'if_condition':
      return [
        _FieldDef('expression', 'node_config.if_condition.expression.label', hint: 'node_config.if_condition.expression.hint', description: 'node_config.if_condition.expression.description'),
        _FieldDef('continue_on_error', 'node_config.if_condition.continue_on_error.label', hint: 'node_config.if_condition.continue_on_error.hint', description: 'node_config.if_condition.continue_on_error.description'),
      ];
    case 'evaluate_rules':
      // Decision tables run *inside* the rule engine — author a rule with
      // rule_type=decision_table over in Rules, then point this node at the
      // event_type those rules listen on. The activity returns the input
      // dict enriched with `_rule_results` and `_rules_matched`, which an
      // If Condition / Switch node can branch on.
      return [
        _FieldDef('event_type', 'node_config.evaluate_rules.event_type.label', hint: 'node_config.evaluate_rules.event_type.hint', description: 'node_config.evaluate_rules.event_type.description'),
        _FieldDef('dry_run', 'node_config.evaluate_rules.dry_run.label', hint: 'node_config.evaluate_rules.dry_run.hint', description: 'node_config.evaluate_rules.dry_run.description'),
      ];
    case 'run_code':
      return [_FieldDef('code', 'node_config.run_code.code.label', description: 'node_config.run_code.code.description', multiline: true),
          _FieldDef('language', 'node_config.run_code.language.label', hint: 'node_config.run_code.language.hint'),
          _FieldDef('continue_on_error', 'node_config.run_code.continue_on_error.label', hint: 'node_config.run_code.continue_on_error.hint')];
    case 'db_query':
      return [_FieldDef('sql', 'node_config.db_query.sql.label', hint: 'node_config.db_query.sql.hint', multiline: true), _FieldDef('credential_id', 'node_config.db_query.credential_id.label')];
    case 'send_email':
      return [_FieldDef('to', 'node_config.send_email.to.label', hint: 'node_config.send_email.to.hint'), _FieldDef('subject', 'node_config.send_email.subject.label'),
          _FieldDef('body', 'node_config.send_email.body.label', multiline: true), _FieldDef('credential_id', 'node_config.send_email.credential_id.label')];
    case 'delay':
      return [_FieldDef('seconds', 'node_config.delay.seconds.label', hint: 'node_config.delay.seconds.hint')];
    case 'imap_trigger':
      return [
        _FieldDef('credential_id', 'node_config.imap_trigger.credential_id.label', description: 'node_config.imap_trigger.credential_id.description'),
        _FieldDef('folder', 'node_config.imap_trigger.folder.label', hint: 'node_config.imap_trigger.folder.hint'),
        _FieldDef('poll_cron', 'node_config.imap_trigger.poll_cron.label', hint: 'node_config.imap_trigger.poll_cron.hint', description: 'node_config.imap_trigger.poll_cron.description'),
        _FieldDef('mark_as_read', 'node_config.imap_trigger.mark_as_read.label', hint: 'node_config.imap_trigger.mark_as_read.hint', description: 'node_config.imap_trigger.mark_as_read.description'),
        _FieldDef('max_emails_per_poll', 'node_config.imap_trigger.max_emails_per_poll.label', hint: 'node_config.imap_trigger.max_emails_per_poll.hint'),
      ];
    case 'gmail_send':
      return [_FieldDef('to', 'node_config.gmail_send.to.label', hint: 'node_config.gmail_send.to.hint'), _FieldDef('subject', 'node_config.gmail_send.subject.label', hint: 'node_config.gmail_send.subject.hint'),
          _FieldDef('body', 'node_config.gmail_send.body.label', multiline: true), _FieldDef('body_html', 'node_config.gmail_send.body_html.label', multiline: true),
          _FieldDef('cc', 'node_config.gmail_send.cc.label'), _FieldDef('bcc', 'node_config.gmail_send.bcc.label'),
          _FieldDef('credential_id', 'node_config.gmail_send.credential_id.label', description: 'node_config.gmail_send.credential_id.description')];
    case 'gmail_read':
      return [_FieldDef('query', 'node_config.gmail_read.query.label', hint: 'node_config.gmail_read.query.hint', description: 'node_config.gmail_read.query.description'),
          _FieldDef('max_results', 'node_config.gmail_read.max_results.label', hint: 'node_config.gmail_read.max_results.hint'), _FieldDef('mark_as_read', 'node_config.gmail_read.mark_as_read.label', hint: 'node_config.gmail_read.mark_as_read.hint'),
          _FieldDef('credential_id', 'node_config.gmail_read.credential_id.label')];
    case 'outlook_send':
      return [_FieldDef('to', 'node_config.outlook_send.to.label', hint: 'node_config.outlook_send.to.hint'), _FieldDef('subject', 'node_config.outlook_send.subject.label'),
          _FieldDef('body', 'node_config.outlook_send.body.label', multiline: true), _FieldDef('body_html', 'node_config.outlook_send.body_html.label', multiline: true),
          _FieldDef('cc', 'node_config.outlook_send.cc.label'), _FieldDef('save_to_sent', 'node_config.outlook_send.save_to_sent.label', hint: 'node_config.outlook_send.save_to_sent.hint'),
          _FieldDef('credential_id', 'node_config.outlook_send.credential_id.label', description: 'node_config.outlook_send.credential_id.description')];
    case 'outlook_read':
      return [_FieldDef('folder', 'node_config.outlook_read.folder.label', hint: 'node_config.outlook_read.folder.hint', description: 'node_config.outlook_read.folder.description'),
          _FieldDef('filter_query', 'node_config.outlook_read.filter_query.label', hint: 'node_config.outlook_read.filter_query.hint'), _FieldDef('max_results', 'node_config.outlook_read.max_results.label', hint: 'node_config.outlook_read.max_results.hint'),
          _FieldDef('mark_as_read', 'node_config.outlook_read.mark_as_read.label', hint: 'node_config.outlook_read.mark_as_read.hint'), _FieldDef('credential_id', 'node_config.outlook_read.credential_id.label')];
    case 's3':
      return [_FieldDef('operation', 'node_config.s3.operation.label', hint: 'node_config.s3.operation.hint', description: 'node_config.s3.operation.description'),
          _FieldDef('bucket', 'node_config.s3.bucket.label'), _FieldDef('key', 'node_config.s3.key.label', hint: 'node_config.s3.key.hint'),
          _FieldDef('body', 'node_config.s3.body.label', description: 'node_config.s3.body.description'),
          _FieldDef('content_type', 'node_config.s3.content_type.label', hint: 'node_config.s3.content_type.hint'), _FieldDef('region', 'node_config.s3.region.label', hint: 'node_config.s3.region.hint'),
          _FieldDef('credential_id', 'node_config.s3.credential_id.label', description: 'node_config.s3.credential_id.description')];
    case 'google_drive':
      return [_FieldDef('operation', 'node_config.google_drive.operation.label', hint: 'node_config.google_drive.operation.hint', description: 'node_config.google_drive.operation.description'),
          _FieldDef('file_id', 'node_config.google_drive.file_id.label'), _FieldDef('file_name', 'node_config.google_drive.file_name.label', hint: 'node_config.google_drive.file_name.hint'),
          _FieldDef('folder_id', 'node_config.google_drive.folder_id.label'), _FieldDef('mime_type', 'node_config.google_drive.mime_type.label'),
          _FieldDef('body', 'node_config.google_drive.body.label'), _FieldDef('query', 'node_config.google_drive.query.label'),
          _FieldDef('credential_id', 'node_config.google_drive.credential_id.label', description: 'node_config.google_drive.credential_id.description')];
    case 'excel_read':
      return [_FieldDef('file_base64', 'node_config.excel_read.file_base64.label', hint: 'node_config.excel_read.file_base64.hint', description: 'node_config.excel_read.file_base64.description'),
          _FieldDef('sheet_name', 'node_config.excel_read.sheet_name.label'), _FieldDef('has_header', 'node_config.excel_read.has_header.label', hint: 'node_config.excel_read.has_header.hint'),
          _FieldDef('max_rows', 'node_config.excel_read.max_rows.label', hint: 'node_config.excel_read.max_rows.hint')];
    case 'excel_write':
      return [_FieldDef('sheet_name', 'node_config.excel_write.sheet_name.label', hint: 'node_config.excel_write.sheet_name.hint'), _FieldDef('include_header', 'node_config.excel_write.include_header.label', hint: 'node_config.excel_write.include_header.hint')];
    case 'claude_llm':
      return [_FieldDef('prompt', 'node_config.claude_llm.prompt.label', hint: 'node_config.claude_llm.prompt.hint', multiline: true),
          _FieldDef('system_prompt', 'node_config.claude_llm.system_prompt.label', multiline: true),
          _FieldDef('model', 'node_config.claude_llm.model.label', hint: 'node_config.claude_llm.model.hint', description: 'node_config.claude_llm.model.description'),
          _FieldDef('max_tokens', 'node_config.claude_llm.max_tokens.label', hint: 'node_config.claude_llm.max_tokens.hint'), _FieldDef('temperature', 'node_config.claude_llm.temperature.label', hint: 'node_config.claude_llm.temperature.hint'),
          _FieldDef('credential_id', 'node_config.claude_llm.credential_id.label', description: 'node_config.claude_llm.credential_id.description')];
    case 'agent_node':
      return [
        _FieldDef('agent_id', 'node_config.agent_node.agent_id.label', description: 'node_config.agent_node.agent_id.description'),
        _FieldDef('input', 'node_config.agent_node.input.label', hint: 'node_config.agent_node.input.hint', multiline: true),
      ];
    case 'agent_graph_node':
      // Phase-E2 multi-agent dispatch. ``spec`` is an
      // AgentGraphSpec JSON: {"entry": "...", "nodes": [{"id": "...",
      // "agent_id": "<uuid>", "next": [...], "branch": "key==val"}]}.
      // Recursion is bounded server-side by smart_llm.orchestrator
      // MAX_DEPTH (3) — depth & cycles are validated before any LLM
      // call fires.
      return [
        _FieldDef('spec', 'node_config.agent_graph_node.spec.label', hint: 'node_config.agent_graph_node.spec.hint', description: 'node_config.agent_graph_node.spec.description', multiline: true),
        _FieldDef('input', 'node_config.agent_graph_node.input.label', hint: 'node_config.agent_graph_node.input.hint', description: 'node_config.agent_graph_node.input.description', multiline: true),
      ];
    case 'tool_node':
      // Skill-name comes pre-filled from the palette's dynamic TOOLS
      // section. ``agent_id`` is optional — when set, the tool runs
      // against that agent's provider/model/key; otherwise the host
      // falls back to the company's default agent.
      return [
        _FieldDef('skill_name', 'node_config.tool_node.skill_name.label', description: 'node_config.tool_node.skill_name.description'),
        _FieldDef('agent_id', 'node_config.tool_node.agent_id.label', description: 'node_config.tool_node.agent_id.description'),
        _FieldDef('input', 'node_config.tool_node.input.label', hint: 'node_config.tool_node.input.hint', multiline: true),
      ];
    case 'stripe':
      return [_FieldDef('endpoint', 'node_config.stripe.endpoint.label', hint: 'node_config.stripe.endpoint.hint', description: 'node_config.stripe.endpoint.description'),
          _FieldDef('method', 'node_config.stripe.method.label', hint: 'node_config.stripe.method.hint'), _FieldDef('data', 'node_config.stripe.data.label', multiline: true),
          _FieldDef('credential_id', 'node_config.stripe.credential_id.label', description: 'node_config.stripe.credential_id.description')];
    case 'mailchimp':
      return [_FieldDef('operation', 'node_config.mailchimp.operation.label', hint: 'node_config.mailchimp.operation.hint', description: 'node_config.mailchimp.operation.description'),
          _FieldDef('list_id', 'node_config.mailchimp.list_id.label'), _FieldDef('email', 'node_config.mailchimp.email.label', hint: 'node_config.mailchimp.email.hint'),
          _FieldDef('merge_fields', 'node_config.mailchimp.merge_fields.label', hint: 'node_config.mailchimp.merge_fields.hint', multiline: true),
          _FieldDef('tags', 'node_config.mailchimp.tags.label', hint: 'node_config.mailchimp.tags.hint'),
          _FieldDef('credential_id', 'node_config.mailchimp.credential_id.label', description: 'node_config.mailchimp.credential_id.description')];

    // ── New control-flow node types ──────────────────────────────────────────

    case 'wait_approval':
      return [
        _FieldDef('approver_email', 'node_config.wait_approval.approver_email.label', hint: 'node_config.wait_approval.approver_email.hint', description: 'node_config.wait_approval.approver_email.description'),
        _FieldDef('prompt', 'node_config.wait_approval.prompt.label', hint: 'node_config.wait_approval.prompt.hint', description: 'node_config.wait_approval.prompt.description', multiline: true),
        _FieldDef('label', 'node_config.wait_approval.label.label', hint: 'node_config.wait_approval.label.hint', description: 'node_config.wait_approval.label.description'),
        _FieldDef('timeout_hours', 'node_config.wait_approval.timeout_hours.label', hint: 'node_config.wait_approval.timeout_hours.hint', description: 'node_config.wait_approval.timeout_hours.description'),
        _FieldDef('continue_on_error', 'node_config.wait_approval.continue_on_error.label', hint: 'node_config.wait_approval.continue_on_error.hint', description: 'node_config.wait_approval.continue_on_error.description'),
      ];

    case 'call_workflow':
      return [
        _FieldDef('sub_workflow_id', 'node_config.call_workflow.sub_workflow_id.label', hint: 'node_config.call_workflow.sub_workflow_id.hint', description: 'node_config.call_workflow.sub_workflow_id.description'),
        _FieldDef('timeout_hours', 'node_config.call_workflow.timeout_hours.label', hint: 'node_config.call_workflow.timeout_hours.hint', description: 'node_config.call_workflow.timeout_hours.description'),
        _FieldDef('continue_on_error', 'node_config.call_workflow.continue_on_error.label', hint: 'node_config.call_workflow.continue_on_error.hint', description: 'node_config.call_workflow.continue_on_error.description'),
      ];

    case 'for_each':
      return [
        _FieldDef('items_path', 'node_config.for_each.items_path.label', hint: 'node_config.for_each.items_path.hint', description: 'node_config.for_each.items_path.description'),
        _FieldDef('body_nodes', 'node_config.for_each.body_nodes.label', description: 'node_config.for_each.body_nodes.description', multiline: true),
        _FieldDef('body_edges', 'node_config.for_each.body_edges.label', description: 'node_config.for_each.body_edges.description', multiline: true),
        _FieldDef('continue_on_error', 'node_config.for_each.continue_on_error.label', hint: 'node_config.for_each.continue_on_error.hint', description: 'node_config.for_each.continue_on_error.description'),
      ];

    case 'switch':
      return [
        _FieldDef('expression', 'node_config.switch.expression.label', hint: 'node_config.switch.expression.hint', description: 'node_config.switch.expression.description'),
        _FieldDef('cases', 'node_config.switch.cases.label', hint: 'node_config.switch.cases.hint', description: 'node_config.switch.cases.description', multiline: true),
        _FieldDef('default_case', 'node_config.switch.default_case.label', hint: 'node_config.switch.default_case.hint', description: 'node_config.switch.default_case.description'),
        _FieldDef('continue_on_error', 'node_config.switch.continue_on_error.label', hint: 'node_config.switch.continue_on_error.hint'),
      ];

    case 'merge':
      return [
        _FieldDef('mode', 'node_config.merge.mode.label', hint: 'node_config.merge.mode.hint', description: 'node_config.merge.mode.description'),
      ];

    default:
      return [];
  }
}
