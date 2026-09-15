import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/builder_provider.dart';
import '../../../widgets/common/drag_data.dart';
import '../element_renderer.dart';

class ContainerElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ContainerElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<ContainerElement> createState() => _ContainerElementState();
}

class _ContainerElementState extends ConsumerState<ContainerElement> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    final children = widget.element.children ?? [];
    final minHeight =
        (widget.element.config['minHeight'] as num?)?.toDouble() ?? 80.0;
    final selectedId =
        ref.watch(builderProvider.select((s) => s.selectedElementId));

    final gap = (widget.element.config['gap'] as num?)?.toDouble() ?? 0.0;
    final mainAxis = _parseMainAxis(
        widget.element.config['mainAxisAlignment'] as String? ?? 'start');
    final crossAxis = _parseCrossAxis(
        widget.element.config['crossAxisAlignment'] as String? ?? 'stretch');

    if (widget.mode != RenderMode.builder) {
      return Container(
        constraints: BoxConstraints(minHeight: minHeight),
        child: children.isNotEmpty
            ? Column(
                mainAxisAlignment: mainAxis,
                crossAxisAlignment: crossAxis,
                mainAxisSize: MainAxisSize.min,
                children: _withGaps(
                  children
                      .map((c) => ElementRenderer(
                          element: c,
                          mode: widget.mode,
                          pageId: widget.pageId))
                      .toList(),
                  gap,
                ),
              )
            : const SizedBox.shrink(),
      );
    }

    // Builder mode: show drop zone inside container
    return DragTarget<PaletteDrag>(
      onWillAcceptWithDetails: (_) {
        setState(() => _accepting = true);
        return true;
      },
      onLeave: (_) => setState(() => _accepting = false),
      onAcceptWithDetails: (details) {
        setState(() => _accepting = false);
        ref.read(builderProvider.notifier).addChildElement(
              widget.element.id,
              details.data.type,
            );
      },
      builder: (context, candidates, rejected) {
        final active = _accepting || candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: BoxDecoration(
            color: active
                ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            border: Border.all(
              color: active
                  ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.5)
                  : OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.2),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: mainAxis,
            crossAxisAlignment: crossAxis,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Existing children with optional gap
              ..._withGaps(
                children.map((c) => _ChildWrapper(
                      element: c,
                      isSelected: selectedId == c.id,
                      mode: widget.mode,
                      pageId: widget.pageId,
                    )).toList(),
                gap,
              ),

              // Bottom drop hint
              Padding(
                padding: const EdgeInsets.all(OTokens.s2),
                child: Center(
                  child: Text(
                    children.isEmpty
                        ? (active ? '+ Drop widget here' : 'Drop widget here')
                        : (active ? '+ Add widget' : ''),
                    style: TextStyle(
                      fontSize: OTokens.textXs,
                      color: active
                          ? OPaletteScope.of(context).primaryBlue
                          : OPaletteScope.of(context).textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

MainAxisAlignment _parseMainAxis(String v) => switch (v) {
      'center' => MainAxisAlignment.center,
      'end' => MainAxisAlignment.end,
      'spaceBetween' || 'between' => MainAxisAlignment.spaceBetween,
      'spaceAround' || 'around' => MainAxisAlignment.spaceAround,
      'spaceEvenly' || 'evenly' => MainAxisAlignment.spaceEvenly,
      _ => MainAxisAlignment.start,
    };

CrossAxisAlignment _parseCrossAxis(String v) => switch (v) {
      'start' => CrossAxisAlignment.start,
      'center' => CrossAxisAlignment.center,
      'end' => CrossAxisAlignment.end,
      'baseline' => CrossAxisAlignment.baseline,
      _ => CrossAxisAlignment.stretch,
    };

List<Widget> _withGaps(List<Widget> children, double gap) {
  if (gap <= 0 || children.length <= 1) return children;
  final result = <Widget>[];
  for (int i = 0; i < children.length; i++) {
    if (i > 0) result.add(SizedBox(height: gap));
    result.add(children[i]);
  }
  return result;
}

class _ChildWrapper extends ConsumerWidget {
  final PageElement element;
  final bool isSelected;
  final RenderMode mode;
  final String pageId;

  const _ChildWrapper({
    required this.element,
    required this.isSelected,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: OTokens.s1, vertical: OTokens.s1),
      child: GestureDetector(
        onTap: () =>
            ref.read(builderProvider.notifier).selectElement(element.id),
        child: Stack(
          children: [
            ElementRenderer(element: element, mode: mode, pageId: pageId),
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(OTokens.radiusSm),
                      border: Border.all(
                          color: OPaletteScope.of(context).primaryBlue, width: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
