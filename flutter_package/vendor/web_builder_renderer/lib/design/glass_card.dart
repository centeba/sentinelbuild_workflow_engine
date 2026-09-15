import 'package:flutter/material.dart';
import 'palette.dart';
import 'tokens.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? glowColor;
  final bool topGlow;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool selected;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = OTokens.radiusLg,
    this.padding,
    this.glowColor,
    this.topGlow = false,
    this.width,
    this.height,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveGlow = glowColor ?? OPaletteScope.of(context).primaryBlue;

    Widget card = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: OPaletteScope.of(context).bgGlass,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: selected
              ? effectiveGlow.withValues(alpha: 0.7)
              : OPaletteScope.of(context).bgGlassBorder,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: OPalette.shadowDeep,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
          if (selected)
            BoxShadow(
              color: effectiveGlow.withValues(alpha: 0.15),
              blurRadius: 8,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            if (topGlow)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        effectiveGlow.withValues(alpha: 0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            if (padding != null)
              Padding(padding: padding!, child: child)
            else
              child,
          ],
        ),
      ),
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        hoverColor: OPaletteScope.of(context).bgHover.withValues(alpha: 0.5),
        child: card,
      );
    }

    return card;
  }
}

class GlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool small;

  const GlassButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.primary = false,
    this.small = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_hovered
            ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.85)
            : OPaletteScope.of(context).primaryBlue)
        : (_hovered ? OPaletteScope.of(context).bgHover : OPaletteScope.of(context).bgRaised);
    final border =
        widget.primary ? OPaletteScope.of(context).primaryBlue : OPaletteScope.of(context).borderStrong;
    final textColor =
        widget.primary ? OPaletteScope.of(context).textInverse : OPaletteScope.of(context).textPrimary;
    final hPad = widget.small ? OTokens.s3 : OTokens.s5;
    final vPad = widget.small ? OTokens.s2 : OTokens.s3;
    final fontSize = widget.small ? OTokens.textSm : OTokens.textBase;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(OTokens.radiusFull),
              border: Border.all(color: border, width: 1),
              boxShadow: widget.primary
                  ? [
                      BoxShadow(
                        color: OPaletteScope.of(context).primaryBlue.withValues(alpha: _hovered ? 0.3 : 0.15),
                        blurRadius: _hovered ? 12 : 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: fontSize + 2, color: textColor),
                  SizedBox(width: widget.small ? OTokens.s1 : OTokens.s2),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.01,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
