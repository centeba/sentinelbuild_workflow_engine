import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';

class AccordionElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const AccordionElement({super.key, required this.element, required this.mode});

  @override
  State<AccordionElement> createState() => _AccordionElementState();
}

class _AccordionElementState extends State<AccordionElement> {
  late Set<int> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = {0};
  }

  @override
  Widget build(BuildContext context) {
    final rawItems = widget.element.config['items'];
    final items = (rawItems is List) ? rawItems.cast<Map>() : <Map>[];

    return Column(
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final isOpen = _expanded.contains(i);
        final isLast = i == items.length - 1;

        return _AccordionItem(
          title: item['title'] as String? ?? 'Item ${i + 1}',
          content: item['content'] as String? ?? '',
          isOpen: isOpen,
          isLast: isLast,
          onToggle: () {
            setState(() {
              if (isOpen) {
                _expanded.remove(i);
              } else {
                _expanded.add(i);
              }
            });
          },
        );
      }).toList(),
    );
  }
}

class _AccordionItem extends StatelessWidget {
  final String title;
  final String content;
  final bool isOpen;
  final bool isLast;
  final VoidCallback onToggle;

  const _AccordionItem({
    required this.title,
    required this.content,
    required this.isOpen,
    required this.isLast,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.bgGlass,
        border: Border(
          top: BorderSide(color: pal.borderSubtle),
          bottom: isLast ? BorderSide(color: pal.borderSubtle) : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: OTokens.s4, vertical: OTokens.s4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: OTokens.textBase,
                        fontWeight: FontWeight.w500,
                        color: pal.textBright,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(LucideIcons.chevronDown,
                        size: 16, color: pal.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  OTokens.s4, 0, OTokens.s4, OTokens.s4),
              child: Text(
                content,
                style: GoogleFonts.inter(
                  fontSize: OTokens.textSm,
                  color: pal.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
