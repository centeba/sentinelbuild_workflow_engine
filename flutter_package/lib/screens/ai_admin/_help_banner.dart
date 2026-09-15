import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';

/// Stable identifier for each tab's banner — controls which entries
/// of the dismiss-state cache apply.
enum HelpBannerKind { agents, skills, tools }

/// SharedPreferences key prefix. One entry per [HelpBannerKind] so
/// dismissing one tab doesn't suppress the others.
const String _kPrefsPrefix = 'ai_admin_banner_dismissed_';

String _prefsKey(HelpBannerKind kind) => '$_kPrefsPrefix${kind.name}';

/// In-memory hydrate cache. Populated lazily from
/// SharedPreferences on first build of each banner so we don't pay
/// an async hop on every rebuild. The cache is single-process — the
/// instant we resolve a key, all subsequent rebuilds of the same
/// banner read directly from this set.
final Set<HelpBannerKind> _dismissedCache = {};
final Set<HelpBannerKind> _hydrated = {};

class HelpBanner extends StatefulWidget {
  const HelpBanner({super.key, required this.kind});

  final HelpBannerKind kind;

  @override
  State<HelpBanner> createState() => _HelpBannerState();
}

class _HelpBannerState extends State<HelpBanner> {
  /// ``true`` once SharedPreferences has been consulted for this
  /// banner's kind. Until then we render nothing — better a single
  /// frame of empty than a flash of the banner that immediately
  /// disappears when the persisted state arrives.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    if (_hydrated.contains(widget.kind)) {
      // Another instance of this banner already hydrated this kind in
      // the current session — read the cache synchronously.
      if (mounted) setState(() => _ready = true);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey(widget.kind)) == true) {
        _dismissedCache.add(widget.kind);
      }
    } catch (_) {
      // SharedPreferences can fail on first run / sandboxed contexts.
      // Fall back to in-memory only — the banner re-shows next visit
      // but never crashes.
    }
    _hydrated.add(widget.kind);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _dismiss() async {
    setState(() => _dismissedCache.add(widget.kind));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey(widget.kind), true);
    } catch (_) {
      // Best-effort persistence — see _hydrate.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    if (_dismissedCache.contains(widget.kind)) return const SizedBox.shrink();

    final body = switch (widget.kind) {
      HelpBannerKind.agents => context.t('ai_admin.banner.agents'),
      HelpBannerKind.skills => context.t('ai_admin.banner.skills'),
      HelpBannerKind.tools => context.t('ai_admin.banner.tools'),
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: AppTheme.bgSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1, right: 10),
              child: Icon(Icons.info_outline,
                  size: 16, color: AppTheme.textSecondary),
            ),
            Expanded(
              child: Text(
                body,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
            IconButton(
              tooltip: context.t('common.dismiss'),
              icon: const Icon(Icons.close,
                  size: 14, color: AppTheme.textSecondary),
              visualDensity: VisualDensity.compact,
              onPressed: _dismiss,
            ),
          ],
        ),
      ),
    );
  }
}
