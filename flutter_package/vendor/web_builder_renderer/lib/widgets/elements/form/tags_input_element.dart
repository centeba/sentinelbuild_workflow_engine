import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';

class TagsInputElement extends StatefulWidget {
  final PageElement element;
  final RenderMode mode;

  const TagsInputElement({super.key, required this.element, required this.mode});

  @override
  State<TagsInputElement> createState() => _TagsInputElementState();
}

class _TagsInputElementState extends State<TagsInputElement> {
  final List<String> _tags = [];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
      setState(() => _tags.add(trimmed));
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = widget.element.config['label'] as String? ?? 'Tags';
    final placeholder = widget.element.config['placeholder'] as String? ?? 'Add tag...';
    final interactive = widget.mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      child: Container(
        padding: const EdgeInsets.all(OTokens.s2),
        decoration: BoxDecoration(
          color: pal.bgSurface,
          borderRadius: BorderRadius.circular(OTokens.radiusSm),
          border: Border.all(color: pal.borderSubtle),
        ),
        child: Wrap(
          spacing: OTokens.s2,
          runSpacing: OTokens.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._tags.map((tag) => _Chip(
                  label: tag,
                  onRemove: interactive ? () => setState(() => _tags.remove(tag)) : null,
                )),
            if (interactive)
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _controller,
                  style: GoogleFonts.inter(
                      fontSize: OTokens.textXs, color: pal.textPrimary),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: GoogleFonts.inter(
                        fontSize: OTokens.textXs, color: pal.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: OTokens.s2, vertical: OTokens.s2),
                  ),
                  onSubmitted: _addTag,
                ),
              )
            else
              Text(placeholder,
                  style: GoogleFonts.inter(
                      fontSize: OTokens.textXs, color: pal.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;

  const _Chip({required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: OTokens.s2, vertical: 3),
      decoration: BoxDecoration(
        color: pal.primaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(OTokens.radiusFull),
        border: Border.all(color: pal.primaryBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: OTokens.textXs,
                  color: pal.primaryBlue,
                  fontWeight: FontWeight.w500)),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(LucideIcons.x, size: 10, color: pal.primaryBlue),
            ),
          ],
        ],
      ),
    );
  }
}
