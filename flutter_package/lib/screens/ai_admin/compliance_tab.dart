import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';
import 'ai_admin_api.dart';

/// PII & AI compliance tab — sets the company-wide PII masking policy and the
/// optional category allowlist that the smart-llm masking firewall enforces on
/// AI egress. The platform default is `enforce` (masking on out-of-the-box); a
/// company admin uses this to relax or tighten it. Per-agent overrides live on
/// each agent (they may only tighten). See docs/pii-masking-compliance.md.
class ComplianceTab extends ConsumerStatefulWidget {
  const ComplianceTab({super.key});

  @override
  ConsumerState<ComplianceTab> createState() => _ComplianceTabState();
}

class _ComplianceTabState extends ConsumerState<ComplianceTab> {
  static const _policies = ['off', 'detect-only', 'enforce', 'strict'];
  // The firewall's detector categories. Empty selection = mask every type.
  static const _categories = [
    'SSN',
    'CREDIT_CARD',
    'EMAIL',
    'PHONE',
    'IBAN',
    'IPV4',
    'IPV6',
    'MRN',
    'DOB',
  ];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _policy = 'enforce';
  final Set<String> _selectedCategories = {};

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
      final s = await ref.read(aiAdminApiProvider).getCompanySettings();
      if (!mounted) return;
      final policy = s['pii_masking_policy'];
      final cats = (s['pii_categories'] as List?)?.cast<String>() ?? const [];
      setState(() {
        _policy = (policy is String && _policies.contains(policy)) ? policy : 'enforce';
        _selectedCategories
          ..clear()
          ..addAll(cats.map((c) => c.toUpperCase()));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(aiAdminApiProvider).updateCompanyPii(
            policy: _policy,
            categories: _selectedCategories.toList()..sort(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('ai_admin.compliance.saved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.t('ai_admin.compliance.save_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('ai_admin.compliance.title'),
              style: const TextStyle(
                  color: AppTheme.textBright,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(context.t('ai_admin.compliance.intro'),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 20),
          // Policy selector.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DropdownButtonFormField<String>(
              initialValue: _policy,
              decoration: InputDecoration(
                labelText: context.t('ai_admin.field.pii_policy'),
                helperText: context.t('ai_admin.compliance.policy_help'),
                helperMaxLines: 3,
              ),
              dropdownColor: AppTheme.bgRaised,
              items: _policies
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(context.t('ai_admin.pii_policy.$p')),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _policy = v ?? 'enforce'),
            ),
          ),
          const SizedBox(height: 20),
          Text(context.t('ai_admin.compliance.categories'),
              style: const TextStyle(
                  color: AppTheme.textBright, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(context.t('ai_admin.compliance.categories_help'),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _categories.map((c) {
              final selected = _selectedCategories.contains(c);
              return FilterChip(
                label: Text(c),
                selected: selected,
                onSelected: (on) => setState(() {
                  if (on) {
                    _selectedCategories.add(c);
                  } else {
                    _selectedCategories.remove(c);
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving
                ? context.t('ai_admin.saving')
                : context.t('common.save')),
          ),
        ],
      ),
    );
  }
}
