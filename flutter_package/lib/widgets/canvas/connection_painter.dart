import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/workflow_node.dart';
import '../../models/workflow_edge.dart';

/// Draws bezier curve connections between workflow nodes.
/// Edges are colour-coded by their branch label:
///   null / unconditional → indigo
///   "true" / "success"   → green
///   "false" / "error"    → red
///   "switch_*" or other  → amber
///
/// A small text label is drawn at the midpoint of each labelled edge.
class ConnectionPainter extends CustomPainter {
  final List<WorkflowNode> nodes;
  final List<WorkflowEdge> edges;
  final WorkflowNode? draggingFrom;
  final Offset? draggingEnd;

  const ConnectionPainter({
    required this.nodes,
    required this.edges,
    this.draggingFrom,
    this.draggingEnd,
  });

  static const _nodeWidth = 180.0;
  static const _nodeHeaderHeight = 40.0;
  static const _portOffset = 12.0;

  Offset _outputPort(WorkflowNode node) =>
      Offset(node.position.dx + _nodeWidth, node.position.dy + _nodeHeaderHeight + _portOffset);

  Offset _inputPort(WorkflowNode node) =>
      Offset(node.position.dx, node.position.dy + _nodeHeaderHeight + _portOffset);

  /// Returns the stroke colour for a given branch label.
  static Color _branchColor(String? branch) {
    switch (branch) {
      case 'true':
      case 'success':
        return const Color(0xFF22C55E); // green-500
      case 'false':
      case 'error':
        return const Color(0xFFEF4444); // red-500
      case null:
        return const Color(0xFF6366F1); // indigo-500 (default)
      default:
        // Switch case labels
        return const Color(0xFFF59E0B); // amber-500
    }
  }

  /// Human-readable label for a branch (strip "switch_" prefix).
  static String? _branchLabel(String? branch) {
    if (branch == null) return null;
    return branch.startsWith('switch_') ? branch.substring(7) : branch;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};

    // Draw established edges
    for (final edge in edges) {
      final from = nodeMap[edge.from];
      final to = nodeMap[edge.to];
      if (from == null || to == null) continue;

      final p1 = _outputPort(from);
      final p2 = _inputPort(to);
      final color = _branchColor(edge.branch);
      final label = _branchLabel(edge.branch);

      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      _drawBezier(canvas, p1, p2, paint);

      if (label != null) {
        _drawLabel(canvas, p1, p2, label, color);
      }
    }

    // Draw in-progress edge while dragging
    if (draggingFrom != null && draggingEnd != null) {
      final p1 = _outputPort(draggingFrom!);
      final draftPaint = Paint()
        ..color = const Color(0xFF6366F1).withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      _drawBezier(canvas, p1, draggingEnd!, draftPaint);
    }
  }

  void _drawBezier(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dx = (p2.dx - p1.dx).abs() * 0.5;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
    canvas.drawPath(path, paint);

    // Arrow tip
    final arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    // Approximate tangent direction at p2
    final ctrlNear = Offset(p2.dx - dx, p2.dy);
    final angle = math.atan2(p2.dy - ctrlNear.dy, p2.dx - ctrlNear.dx);
    _drawArrow(canvas, p2, angle, arrowPaint);
  }

  void _drawArrow(Canvas canvas, Offset tip, double angle, Paint paint) {
    const size = 8.0;
    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(
      tip.dx - size * math.cos(angle - 0.4),
      tip.dy - size * math.sin(angle - 0.4),
    );
    path.lineTo(
      tip.dx - size * math.cos(angle + 0.4),
      tip.dy - size * math.sin(angle + 0.4),
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawLabel(Canvas canvas, Offset p1, Offset p2, String label, Color color) {
    // Midpoint of the cubic bezier (approximated as midpoint of p1→p2)
    final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2 - 10);

    // Background pill
    const fontSize = 10.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const hPad = 5.0;
    const vPad = 2.0;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: mid,
        width: textPainter.width + hPad * 2,
        height: textPainter.height + vPad * 2,
      ),
      const Radius.circular(4),
    );

    canvas.drawRRect(pillRect, Paint()..color = color.withValues(alpha: 0.9));
    textPainter.paint(
      canvas,
      mid - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(ConnectionPainter old) =>
      old.nodes != nodes || old.edges != edges || old.draggingEnd != draggingEnd;
}
