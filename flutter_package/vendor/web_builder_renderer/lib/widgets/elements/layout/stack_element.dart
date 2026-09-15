import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/builder_provider.dart';
import '../../../widgets/common/drag_data.dart';
import '../element_renderer.dart';

class StackElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const StackElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  ConsumerState<StackElement> createState() => _StackElementState();
}

class _StackElementState extends ConsumerState<StackElement> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    final children = widget.element.children ?? [];
    final minHeight =
        (widget.element.config['minHeight'] as num?)?.toDouble() ?? 120.0;
    final selectedId =
        ref.watch(builderProvider.select((s) => s.selectedElementId));

    if (widget.mode != RenderMode.builder) {
      return SizedBox(
        width: double.infinity,
        child: Stack(
          children: children
              .map((c) => ElementRenderer(
                  element: c, mode: widget.mode, pageId: widget.pageId))
              .toList(),
        ),
      );
    }

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
                : OPaletteScope.of(context).bgRaised.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            border: Border.all(
              color: active
                  ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.5)
                  : OPaletteScope.of(context).borderSubtle,
            ),
          ),
          child: Stack(
            children: [
              ...children.map((c) => GestureDetector(
                    onTap: () => ref
                        .read(builderProvider.notifier)
                        .selectElement(c.id),
                    child: Stack(
                      children: [
                        ElementRenderer(
                            element: c,
                            mode: widget.mode,
                            pageId: widget.pageId),
                        if (selectedId == c.id)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      OTokens.radiusSm),
                                  border: Border.all(
                                      color: OPaletteScope.of(context).primaryBlue,
                                      width: 1.5),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )),
              if (children.isEmpty)
                Center(
                  child: Text(
                    active ? '+ Drop layer here' : 'Drop layers here',
                    style: TextStyle(
                      fontSize: OTokens.textXs,
                      color: active
                          ? OPaletteScope.of(context).primaryBlue
                          : OPaletteScope.of(context).textMuted,
                      fontWeight: FontWeight.w500,
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
