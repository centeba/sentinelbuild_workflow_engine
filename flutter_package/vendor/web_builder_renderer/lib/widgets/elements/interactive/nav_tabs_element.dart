import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class NavTabsElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const NavTabsElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<NavTabsElement> createState() => _NavTabsElementState();
}

class _NavTabsElementState extends ConsumerState<NavTabsElement> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final tabs = List<Map<String, dynamic>>.from(
      (widget.element.config['tabs'] as List<dynamic>? ?? []).map(
        (t) => Map<String, dynamic>.from(t as Map? ?? {}),
      ),
    );

    if (tabs.isEmpty) {
      if (widget.mode == RenderMode.builder) {
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: OTokens.s4, vertical: OTokens.s3),
          decoration: BoxDecoration(
            color: pal.bgRaised,
            borderRadius: BorderRadius.circular(OTokens.radiusFull),
            border: Border.all(color: pal.borderSubtle),
          ),
          child: Text(
            'Nav Tabs — configure tabs in Content panel',
            style: TextStyle(
                fontSize: OTokens.textXs, color: pal.textMuted),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(OTokens.s1),
      decoration: BoxDecoration(
        color: pal.bgRaised,
        borderRadius: BorderRadius.circular(OTokens.radiusFull),
        border: Border.all(color: pal.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.asMap().entries.map((entry) {
          final i = entry.key;
          final tab = entry.value;
          final label = tab['label'] as String? ?? 'Tab';
          final isSelected = i == _selected;

          return GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: OTokens.s4, vertical: OTokens.s2),
              decoration: BoxDecoration(
                color: isSelected
                    ? pal.primaryBlue
                    : Colors.transparent,
                borderRadius:
                    BorderRadius.circular(OTokens.radiusFull),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: pal.primaryBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: -2,
                        ),
                      ]
                    : [],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: OTokens.textSm,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: isSelected
                      ? pal.textBright
                      : pal.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
