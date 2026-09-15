import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/builder_provider.dart';
import '../../../widgets/common/drag_data.dart';
import '../element_renderer.dart';

class RowElement extends ConsumerWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const RowElement({
    super.key,
    required this.element,
    required this.mode,
    required this.pageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = element.children ?? [];
    final gap = (element.config['gap'] as num?)?.toDouble() ?? 8.0;
    final mainAxis = _parseMainAxis(
        element.config['mainAxisAlignment'] as String? ?? 'start');
    final crossAxis = _parseCrossAxis(
        element.config['crossAxisAlignment'] as String? ?? 'center');

    if (mode != RenderMode.builder) {
      return Row(
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: crossAxis,
        children: children
            .asMap()
            .entries
            .map((e) => _buildChild(e.value, gap, e.key, children.length))
            .toList(),
      );
    }

    // Builder mode: children + drop zone at end
    return _BuilderRow(
      element: element,
      mode: mode,
      pageId: pageId,
      children: children,
      gap: gap,
      mainAxis: mainAxis,
      crossAxis: crossAxis,
    );
  }

  Widget _buildChild(
      PageElement child, double gap, int index, int total) {
    final flex = (child.config['flex'] as int?) ?? 1;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(left: index > 0 ? gap : 0),
        child: ElementRenderer(
          element: child,
          mode: mode,
          pageId: pageId,
        ),
      ),
    );
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
        'end' => CrossAxisAlignment.end,
        'stretch' => CrossAxisAlignment.stretch,
        'baseline' => CrossAxisAlignment.baseline,
        _ => CrossAxisAlignment.center,
      };
}

class _BuilderRow extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;
  final List<PageElement> children;
  final double gap;
  final MainAxisAlignment mainAxis;
  final CrossAxisAlignment crossAxis;

  const _BuilderRow({
    required this.element,
    required this.mode,
    required this.pageId,
    required this.children,
    required this.gap,
    required this.mainAxis,
    required this.crossAxis,
  });

  @override
  ConsumerState<_BuilderRow> createState() => _BuilderRowState();
}

class _BuilderRowState extends ConsumerState<_BuilderRow> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    final selectedId =
        ref.watch(builderProvider.select((s) => s.selectedElementId));

    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: widget.mainAxis,
        crossAxisAlignment: widget.crossAxis,
        children: [
          // Existing children
          ...widget.children.asMap().entries.map((entry) {
            final i = entry.key;
            final child = entry.value;
            final flex = (child.config['flex'] as int?) ?? 1;
            final isSelected = selectedId == child.id;
            return Expanded(
              flex: flex,
              child: Padding(
                padding: EdgeInsets.only(left: i > 0 ? widget.gap : 0),
                child: _ChildWrapper(
                  element: child,
                  isSelected: isSelected,
                  mode: widget.mode,
                  pageId: widget.pageId,
                ),
              ),
            );
          }),

          // Drop zone at end
          DragTarget<PaletteDrag>(
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
                width: active ? 80 : (widget.children.isEmpty ? double.infinity : 40),
                constraints: const BoxConstraints(minHeight: 60),
                margin: EdgeInsets.only(
                    left: widget.children.isNotEmpty ? widget.gap : 0),
                decoration: BoxDecoration(
                  color: active
                      ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.06)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(OTokens.radiusSm),
                  border: Border.all(
                    color: active
                        ? OPaletteScope.of(context).primaryBlue.withValues(alpha: 0.6)
                        : OPaletteScope.of(context).borderSubtle,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.children.isEmpty
                        ? 'Drop into row'
                        : (active ? '+ Add' : '+'),
                    style: TextStyle(
                      fontSize: OTokens.textXs,
                      color: active
                          ? OPaletteScope.of(context).primaryBlue
                          : OPaletteScope.of(context).textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
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
    return GestureDetector(
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
    );
  }
}
