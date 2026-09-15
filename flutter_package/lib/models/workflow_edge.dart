class WorkflowEdge {
  final String from;
  final String to;

  /// Branch label that controls when this edge is traversed.
  ///
  /// Values:
  ///   null        → unconditional (traversed on any non-error success)
  ///   "true"      → only when the source if_condition matched (true branch)
  ///   "false"     → only when the source if_condition did NOT match
  ///   "success"   → only when the source node completed without error
  ///   "error"     → only when the source node raised an exception
  ///   any string  → switch case label (e.g. "gold", "silver")
  final String? branch;

  const WorkflowEdge({required this.from, required this.to, this.branch});

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        if (branch != null) 'branch': branch,
      };

  factory WorkflowEdge.fromJson(Map<String, dynamic> json) => WorkflowEdge(
        from: json['from'] as String,
        to: json['to'] as String,
        branch: json['branch'] as String?,
      );
}
