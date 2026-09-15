import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../_value_format.dart';
import '../element_renderer.dart';

class CardElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const CardElement({super.key, required this.element, required this.mode, required this.pageId});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    // Default to empty (not "Card Title") so container-style cards — which
    // carry their content as child elements (a heading, a form, a list) rather
    // than a config title — don't show a stray placeholder heading.
    final title = element.config['title'] as String? ?? '';
    final subtitle = element.config['subtitle'] as String? ?? '';
    final body = element.config['body'] as String? ?? '';
    final children = element.children ?? const [];

    // Optional structured fields list — preferred over `body` for
    // record-style cards (Customer / Property / Insurance / Claim).
    // Each entry: `{label, value}`. Empty values render as an em-dash
    // placeholder so the user sees the schema (every expected field
    // is visible) instead of a blank card.
    final rawFields = element.config['fields'];
    final fields = <_CardField>[];
    if (rawFields is List) {
      for (final f in rawFields) {
        if (f is Map) {
          var value = (f['value'] ?? '').toString().trim();
          // Honor `renderer: date` — format ISO timestamps as a friendly date.
          if (value.isNotEmpty && f['renderer'] == 'date') {
            value = friendlyDate(value);
          }
          fields.add(_CardField(
            label: (f['label'] as String?) ?? '',
            value: value.isEmpty ? '—' : value,
            isPlaceholder: value.isEmpty,
          ));
        }
      }
    }

    // `layout: bar` → a horizontal "job info bar" strip of labeled fields with
    // a brand bottom-border (mockup style), instead of the vertical card.
    if (element.config['layout'] == 'bar') {
      return _buildBar(context, fields);
    }

    // Clean, professional surface card (white background, hairline border,
    // soft shadow) — replaces the earlier glassmorphism/blur look, which read
    // as washed-out on the light page canvas.
    return Container(
      decoration: BoxDecoration(
        color: pal.bgSurface,
        borderRadius: BorderRadius.circular(OTokens.radiusLg),
        border: Border.all(color: pal.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(OTokens.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: OTokens.textLg,
                          fontWeight: FontWeight.w600,
                          color: pal.textBright,
                        ),
                      ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: OTokens.s1),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: OTokens.textSm,
                          color: pal.textSecondary,
                        ),
                      ),
                    ],
                    if (fields.isNotEmpty) ...[
                      const SizedBox(height: OTokens.s4),
                      Divider(color: pal.borderSubtle, height: 1),
                      const SizedBox(height: OTokens.s3),
                      for (final f in fields)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  f.label,
                                  style: GoogleFonts.inter(
                                    fontSize: OTokens.textXs,
                                    color: pal.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  f.value,
                                  style: GoogleFonts.inter(
                                    fontSize: OTokens.textSm,
                                    color: f.isPlaceholder
                                        ? pal.textMuted
                                        : pal.textPrimary,
                                    fontStyle: f.isPlaceholder
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else if (body.isNotEmpty) ...[
                      const SizedBox(height: OTokens.s4),
                      Divider(color: pal.borderSubtle, height: 1),
                      const SizedBox(height: OTokens.s4),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: OTokens.textSm,
                          color: pal.textPrimary,
                          height: 1.6,
                        ),
                      ),
                    ],
                    // Render nested child elements (heading, form, list, …).
                    // Container-style cards (Notes / Action items) keep their
                    // real content as children, not in config — without this
                    // the card body was empty (just the placeholder title),
                    // which is why notes/action forms never appeared.
                    if (children.isNotEmpty) ...[
                      if (title.isNotEmpty ||
                          subtitle.isNotEmpty ||
                          fields.isNotEmpty ||
                          body.isNotEmpty)
                        const SizedBox(height: OTokens.s4),
                      for (final child in children)
                        Padding(
                          padding: const EdgeInsets.only(bottom: OTokens.s3),
                          child: ElementRenderer(
                              element: child, mode: mode, pageId: pageId),
                        ),
                    ],
                  ],
                ),
              ),
            );
  }

  /// Horizontal "job info bar": labeled fields in a wrap with a brand
  /// bottom-border. Used for the project header strip (mockup style).
  Widget _buildBar(BuildContext context, List<_CardField> fields) {
    final pal = OPaletteScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.bgSurface,
        border: Border(bottom: BorderSide(color: pal.primaryBlue, width: 3)),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: OTokens.s5, vertical: OTokens.s4),
      child: Wrap(
        spacing: 28,
        runSpacing: 14,
        children: [
          for (final f in fields)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textXs,
                    fontWeight: FontWeight.w700,
                    color: pal.textMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  f.value,
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textSm,
                    fontWeight: FontWeight.w600,
                    color: f.isPlaceholder ? pal.textMuted : pal.textPrimary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CardField {
  final String label;
  final String value;
  final bool isPlaceholder;
  const _CardField({
    required this.label,
    required this.value,
    this.isPlaceholder = false,
  });
}
