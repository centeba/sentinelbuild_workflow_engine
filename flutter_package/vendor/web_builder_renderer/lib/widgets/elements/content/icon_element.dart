import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';

class IconElement extends StatelessWidget {
  final PageElement element;

  const IconElement({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final iconName = element.config['iconName'] as String? ?? 'star';
    final size = (element.config['size'] as num?)?.toDouble() ?? 24.0;
    final pal = OPaletteScope.of(context);
    final color = element.style?.resolvedColor(pal) ?? pal.textSecondary;

    return Padding(
      padding: const EdgeInsets.all(OTokens.s2),
      child: Icon(_resolveIcon(iconName), size: size, color: color),
    );
  }

  IconData _resolveIcon(String name) {
    return switch (name) {
      'star' => LucideIcons.star,
      'check' => LucideIcons.check,
      'x' => LucideIcons.x,
      'alert' => LucideIcons.alertCircle,
      'info' => LucideIcons.info,
      'user' => LucideIcons.user,
      'settings' => LucideIcons.settings,
      'bell' => LucideIcons.bell,
      'mail' => LucideIcons.mail,
      'phone' => LucideIcons.phone,
      'home' => LucideIcons.home,
      'search' => LucideIcons.search,
      'chart' => LucideIcons.barChart2,
      'trending_up' => LucideIcons.trendingUp,
      'trending_down' => LucideIcons.trendingDown,
      'dollar' => LucideIcons.dollarSign,
      'shield' => LucideIcons.shield,
      'lock' => LucideIcons.lock,
      'file' => LucideIcons.fileText,
      'calendar' => LucideIcons.calendar,
      _ => LucideIcons.star,
    };
  }
}
