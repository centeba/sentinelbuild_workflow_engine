import 'package:flutter/material.dart';

class WorkflowNode {
  final String id;
  final String type;
  final String name;
  final Offset position;
  final Map<String, dynamic> config;

  const WorkflowNode({
    required this.id,
    required this.type,
    required this.name,
    required this.position,
    this.config = const {},
  });

  WorkflowNode copyWith({String? type, String? name, Offset? position, Map<String, dynamic>? config}) {
    return WorkflowNode(
      id: id,
      type: type ?? this.type,
      name: name ?? this.name,
      position: position ?? this.position,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'position': {'x': position.dx, 'y': position.dy},
    'config': config,
  };

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    // Defensive: workflows seeded via SQL, AI-generated, or imported
    // from external tools commonly omit the ``position`` field — the
    // backend treats it as builder-only metadata. Previously this
    // factory crashed on the null subscript ``json['position']['x']``,
    // which silently blanked the entire editor (the exception escaped
    // ``_loadWorkflow`` and ``_nodes`` stayed empty). Default to
    // ``Offset.zero`` and let the canvas auto-layout snap.
    final pos = json['position'];
    final dx = (pos is Map && pos['x'] is num)
        ? (pos['x'] as num).toDouble()
        : 0.0;
    final dy = (pos is Map && pos['y'] is num)
        ? (pos['y'] as num).toDouble()
        : 0.0;
    return WorkflowNode(
      id: json['id'] as String,
      type: json['type'] as String,
      name: (json['name'] as String?) ?? '',
      position: Offset(dx, dy),
      config: Map<String, dynamic>.from(
          (json['config'] as Map?) ?? const {}),
    );
  }
}
