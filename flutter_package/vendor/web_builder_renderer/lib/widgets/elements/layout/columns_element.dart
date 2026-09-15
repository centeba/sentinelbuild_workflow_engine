import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/builder_provider.dart';
import '../../../widgets/common/drag_data.dart';
import '../element_renderer.dart';

class ColumnsElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const ColumnsElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = element.config['columnCount'] as int? ?? 2;
    final children = element.children ?? [];
    final selectedId =
        ref.watch(builderProvider.select((s) => s.selectedElementId));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(count, (i) {
        final child = i < children.length &&
                !children[i].id.startsWith('_empty_')
            ? children[i]
            : null;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? OTokens.s3 : 0),
            child: child != null
                ? mode == RenderMode.builder
                    ? GestureDetector(
                        onTap: () => ref
                            .read(builderProvider.notifier)
                            .selectElement(child.id),
                        child: Stack(
                          children: [
                            ElementRenderer(
                                element: child,
                                mode: mode,
                                pageId: pageId),
                            if (selectedId == child.id)
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
                      )
                    : ElementRenderer(
                        element: child, mode: mode, pageId: pageId)
                : mode == RenderMode.builder
                    ? _ColumnDropZone(
                        parentId: element.id,
                        colIndex: i,
                        colNumber: i + 1,
                      )
                    : const SizedBox.shrink(),
          ),
        );
      }),
    );
  }
}

class _ColumnDropZone extends ConsumerStatefulWidget {
  final String parentId;
  final int colIndex;
  final int colNumber;

  const _ColumnDropZone({
    required this.parentId,
    required this.colIndex,
    required this.colNumber,
  });

  @override
  ConsumerState<_ColumnDropZone> createState() => _ColumnDropZoneState();
}

class _ColumnDropZoneState extends ConsumerState<_ColumnDropZone> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<PaletteDrag>(
      onWillAcceptWithDetails: (_) {
        setState(() => _accepting = true);
        return true;
      },
      onLeave: (_) => setState(() => _accepting = false),
      onAcceptWithDetails: (details) {
        setState(() => _accepting = false);
        ref.read(builderProvider.notifier).setColumnChild(
              widget.parentId,
              widget.colIndex,
              details.data.type,
            );
      },
      builder: (context, candidates, rejected) {
        final active = _accepting || candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            color: active
                ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(OTokens.radiusSm),
            border: Border.all(
              color: active
                  ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.5)
                  : OPaletteScope.of(context).borderSubtle.withValues(alpha: 0.4),
              style: BorderStyle.solid,
            ),
          ),
          child: Center(
            child: Text(
              active ? '+ Drop here' : 'Col ${widget.colNumber}',
              style: GoogleFonts.inter(
                fontSize: OTokens.textXs,
                color: active ? OPaletteScope.of(context).primaryBlue : OPaletteScope.of(context).textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}
