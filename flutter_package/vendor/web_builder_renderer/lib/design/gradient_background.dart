import 'package:flutter/material.dart';
import 'palette.dart';

class AnimatedGradientBackground extends StatelessWidget {
  final Widget child;

  const AnimatedGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: OPaletteScope.of(context).bgCanvas, child: child);
  }
}
