import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../services/api_client.dart';
import '../../theme.dart';

/// Settings hub. First tab: **Automation Category** taxonomy editor.
///
/// More tabs (e.g. team, billing, notifications) can be added in the same
/// TabBar — the screen is intentionally lightweight so adding a tab is just
/// another `Tab` + `TabBarView` child.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 1, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
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
            Text(
              context.t('nav.settings'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textBright,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('mit_settings.subtitle'),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppTheme.textBright,
              unselectedLabelColor: AppTheme.textMuted,
              indicatorColor: AppTheme.primary,
              dividerColor: AppTheme.borderSubtle,
              tabs: [
                Tab(text: context.t('mit_settings.tab_automation_category')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  AutomationCategoriesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Automation Category tab ─────────────────────────────────────────────────

class AutomationCategoriesTab extends ConsumerStatefulWidget {
  const AutomationCategoriesTab({super.key});
  @override
  ConsumerState<AutomationCategoriesTab> createState() =>
      _AutomationCategoriesTabState();
}

class _AutomationCategoriesTabState extends ConsumerState<AutomationCategoriesTab> {
  List<Map<String, dynamic>> _categories = [];
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
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/automation-categories');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(resp.data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addCategory() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CategoryEditorDialog(),
    );
    if (result == null) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/automation-categories', data: result);
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editCategory(Map<String, dynamic> cat) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CategoryEditorDialog(initial: cat),
    );
    if (result == null) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.put('/automation-categories/${cat["id"]}',
          data: {'name': result['name'], 'color': result['color']});
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('mit_settings.delete_category_title'),
            style: const TextStyle(color: AppTheme.textBright)),
        content: Text(
          '${ctx.t('mit_settings.delete_category_prefix')} "${cat["name"]}"? '
          '${ctx.t('mit_settings.delete_category_warning')}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t('common.cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorBorder),
            child: Text(ctx.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/automation-categories/${cat["id"]}');
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    final msg = e.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontSize: 12))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              context.t('mit_settings.categories_help'),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          FilledButton.icon(
            onPressed: _addCategory,
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.t('mit_settings.new_category')),
          ),
        ]),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!,
                style: const TextStyle(color: AppTheme.errorText, fontSize: 12)),
          ),
        Expanded(
          child: _categories.isEmpty
              ? Center(
                  child: Text(
                  context.t('mit_settings.no_categories'),
                  style: const TextStyle(color: AppTheme.textMuted),
                ))
              : Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: ListView.separated(
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, color: AppTheme.borderSubtle),
                    itemBuilder: (_, i) => _CategoryRow(
                      category: _categories[i],
                      onEdit: () => _editCategory(_categories[i]),
                      onDelete: () => _deleteCategory(_categories[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final Map<String, dynamic> category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scope = category['scope'] as String? ?? 'user';
    final color = category['color'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _parseColor(color) ?? AppTheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(category['name'] as String? ?? '',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary))),
        _ScopeChip(scope: scope),
        const SizedBox(width: 8),
        IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppTheme.textSecondary,
            onPressed: onEdit),
        IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppTheme.errorText,
            onPressed: onDelete),
      ]),
    );
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var s = hex.replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.tryParse(s, radix: 16) ?? 0xFF6366F1);
  }
}

class _ScopeChip extends StatelessWidget {
  final String scope;
  const _ScopeChip({required this.scope});
  @override
  Widget build(BuildContext context) {
    final isSystem = scope == 'system';
    final isCompany = scope == 'company';
    final bg = isSystem
        ? AppTheme.primaryBg
        : isCompany
            ? AppTheme.successBg
            : AppTheme.bgPage;
    final border = isSystem
        ? AppTheme.primary
        : isCompany
            ? AppTheme.successBorder
            : AppTheme.borderSubtle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Text(
        scope,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

// ── Editor dialog ──────────────────────────────────────────────────────────

class _CategoryEditorDialog extends StatefulWidget {
  /// If non-null, we're editing an existing row — only name/color are sent
  /// back; scope is read-only.
  final Map<String, dynamic>? initial;
  const _CategoryEditorDialog({this.initial});
  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _colorCtrl;
  String _scope = 'user';

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtrl = TextEditingController(text: init?['name'] as String? ?? '');
    _colorCtrl = TextEditingController(text: init?['color'] as String? ?? '');
    _scope = init?['scope'] as String? ?? 'user';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return AlertDialog(
      title: Text(
          isEdit ? context.t('mit_settings.edit_category') : context.t('mit_settings.new_category'),
          style: const TextStyle(color: AppTheme.textBright)),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(labelText: context.t('ai_admin.field.name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _colorCtrl,
            decoration: InputDecoration(
              labelText: context.t('mit_settings.color_optional'),
              // Hint is example hex code — kept literal.
              hintText: '#6366F1',
            ),
          ),
          const SizedBox(height: 16),
          if (!isEdit)
            DropdownButtonFormField<String>(
              value: _scope,
              decoration: InputDecoration(
                labelText: context.t('mit_settings.scope'),
                helperText: context.t('mit_settings.scope_helper'),
                helperMaxLines: 2,
              ),
              items: [
                DropdownMenuItem(value: 'user', child: Text(context.t('mit_settings.scope_user'))),
                DropdownMenuItem(value: 'company', child: Text(context.t('mit_settings.scope_company'))),
                DropdownMenuItem(value: 'system', child: Text(context.t('mit_settings.scope_system'))),
              ],
              onChanged: (v) => setState(() => _scope = v ?? 'user'),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('common.cancel'))),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isEmpty) return;
            Navigator.pop<Map<String, dynamic>>(context, {
              'name': _nameCtrl.text.trim(),
              if (_colorCtrl.text.trim().isNotEmpty) 'color': _colorCtrl.text.trim(),
              if (!isEdit) 'scope': _scope,
            });
          },
          child: Text(isEdit ? context.t('common.save') : context.t('common.create')),
        ),
      ],
    );
  }
}
