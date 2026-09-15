import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'node_widget.dart';
import 'connection_painter.dart';
import '../../models/workflow_node.dart';
import '../../models/workflow_edge.dart';

/// Pan-and-zoom canvas for building workflow DAGs.
class WorkflowCanvas extends StatefulWidget {
  final List<WorkflowNode> nodes;
  final List<WorkflowEdge> edges;
  final WorkflowNode? selectedNode;
  final void Function(WorkflowNode node) onNodeSelected;
  final void Function(String nodeId, Offset position) onNodeMoved;
  final void Function(String fromId, String toId) onEdgeCreated;
  final void Function(String nodeId) onNodeDeleted;
  /// Pinned node outputs from the last execution {nodeId: outputData}.
  final Map<String, Map<String, dynamic>> pinnedOutputs;

  const WorkflowCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    required this.selectedNode,
    required this.onNodeSelected,
    required this.onNodeMoved,
    required this.onEdgeCreated,
    required this.onNodeDeleted,
    this.pinnedOutputs = const {},
  });

  @override
  State<WorkflowCanvas> createState() => _WorkflowCanvasState();
}

class _WorkflowCanvasState extends State<WorkflowCanvas> {
  final TransformationController _transformCtrl = TransformationController();

  // Edge drawing state
  String? _draggingFromNodeId;
  Offset? _draggingEnd;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            // Zoom with mouse wheel
            final scale = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
            final zoomed = _transformCtrl.value.clone()
              ..scale(scale, scale);
            _transformCtrl.value = zoomed;
          }
        },
        child: InteractiveViewer(
          transformationController: _transformCtrl,
          minScale: 0.2,
          maxScale: 3.0,
          constrained: false,
          child: SizedBox(
            width: 4000,
            height: 3000,
            child: Stack(
              children: [
                // Grid background — isolated behind a RepaintBoundary so
                // it's rasterised once and not re-painted every time a
                // node moves (the grid is static).
                RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(4000, 3000),
                    painter: _GridPainter(),
                  ),
                ),
                // Connections layer — its own raster layer so node-body
                // rebuilds don't force a full-canvas re-raster.
                RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(4000, 3000),
                    painter: ConnectionPainter(
                      nodes: widget.nodes,
                      edges: widget.edges,
                      draggingFrom: _draggingFromNodeId != null
                          ? widget.nodes.firstWhere((n) => n.id == _draggingFromNodeId, orElse: () => widget.nodes.first)
                          : null,
                      draggingEnd: _draggingEnd,
                    ),
                  ),
                ),
                // Nodes — each isolated behind a RepaintBoundary so
                // dragging one node only re-rasters that node, not all.
                ...widget.nodes.map((node) => Positioned(
                  left: node.position.dx,
                  top: node.position.dy,
                  child: RepaintBoundary(
                    child: NodeWidget(
                    node: node,
                    isSelected: widget.selectedNode?.id == node.id,
                    pinnedOutput: widget.pinnedOutputs[node.id],
                    onTap: () => widget.onNodeSelected(node),
                    onDragUpdate: (delta) {
                      widget.onNodeMoved(node.id, node.position + delta);
                    },
                    onStartEdge: () {
                      setState(() => _draggingFromNodeId = node.id);
                    },
                    onEndEdge: () {
                      if (_draggingFromNodeId != null && _draggingFromNodeId != node.id) {
                        widget.onEdgeCreated(_draggingFromNodeId!, node.id);
                      }
                      setState(() {
                        _draggingFromNodeId = null;
                        _draggingEnd = null;
                      });
                    },
                    onDelete: () => widget.onNodeDeleted(node.id),
                  ),
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // One drawPoints call instead of ~20k drawCircle calls — far cheaper
    // to raster (and it only paints once now, behind a RepaintBoundary).
    final dotPaint = Paint()
      ..color = const Color(0xFF2D3148) // borderSubtle — dark dots
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const step = 24.0;
    final points = <Offset>[];
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(PointMode.points, points, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
