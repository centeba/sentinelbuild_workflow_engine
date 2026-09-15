// Tiny expression evaluator for `valueFrom` on display widgets (statCard,
// gauge etc.). Page authors write things like:
//
//   "valueFrom": "length(filter(status == 'active'))"
//   "valueFrom": "length()"
//   "valueFrom": "count(status != 'complete')"
//   "valueFrom": "sum(amount)"
//   "valueFrom": "avg(score)"
//
// against a response that's typically a list of records. The grammar is
// intentionally minimal — anything fancier should go through a proper
// expression language. Returns `null` on unrecognised input so the
// widget can fall back gracefully.
library;

/// Top-level entry. [body] is the fetched response (usually a List or a
/// Map with a list under `items` / `data` / `results`).
dynamic evaluateValueFrom(String expression, dynamic body) {
  final src = expression.trim();
  if (src.isEmpty) return null;

  // Unwrap common envelope shapes so `length()` works whether the
  // response is `[...]` or `{items: [...]}`.
  final List items = _toList(body);

  final fn = _ParsedFn.tryParse(src);
  if (fn == null) return null;

  switch (fn.name) {
    case 'length':
    case 'count':
      if (fn.args.isEmpty) return items.length;
      // Nested call form — `length(filter(<predicate>))` (the documented
      // shape): evaluate the inner call, then take its length.
      final innerFn = _ParsedFn.tryParse(fn.args);
      if (innerFn != null) {
        final inner = evaluateValueFrom(fn.args, items);
        if (inner is List) return inner.length;
        if (inner is num) return inner;
        return null;
      }
      // Bare predicate form — `count(status == 'active')`.
      final predicate = _Predicate.tryParse(fn.args);
      if (predicate == null) return null;
      return items.where(predicate.matches).length;

    case 'filter':
      final predicate = _Predicate.tryParse(fn.args);
      if (predicate == null) return null;
      return items.where(predicate.matches).toList();

    case 'sum':
      final field = fn.args.trim();
      if (field.isEmpty) return null;
      return items.fold<num>(0, (acc, e) {
        final v = _read(e, field);
        return acc + (v is num ? v : 0);
      });

    case 'avg':
      final field = fn.args.trim();
      if (field.isEmpty || items.isEmpty) return null;
      final sum = items.fold<num>(0, (acc, e) {
        final v = _read(e, field);
        return acc + (v is num ? v : 0);
      });
      return sum / items.length;

    case 'first':
      return items.isEmpty ? null : items.first;

    case 'last':
      return items.isEmpty ? null : items.last;

    default:
      // Recognise nested calls like `length(filter(<predicate>))` by
      // re-parsing the inner expression as a fn call too.
      final innerFn = _ParsedFn.tryParse(fn.args);
      if (innerFn != null && fn.name == 'length') {
        final inner = evaluateValueFrom(fn.args, items);
        return inner is List ? inner.length : null;
      }
      return null;
  }
}

List _toList(dynamic body) {
  if (body is List) return body;
  if (body is Map) {
    for (final k in const ['items', 'data', 'results', 'rows']) {
      final v = body[k];
      if (v is List) return v;
    }
    return [body];
  }
  return const [];
}

dynamic _read(dynamic row, String field) {
  if (row is Map) return row[field];
  return null;
}

// ── Parsing ────────────────────────────────────────────────────────────

class _ParsedFn {
  final String name;
  final String args;
  const _ParsedFn(this.name, this.args);

  /// Parses `name(args)`. Args is the raw inner string with balanced
  /// parens preserved, so nested calls round-trip. Returns null if the
  /// surface shape doesn't match.
  static _ParsedFn? tryParse(String src) {
    final s = src.trim();
    final open = s.indexOf('(');
    if (open <= 0 || !s.endsWith(')')) return null;
    final name = s.substring(0, open).trim();
    if (name.isEmpty || RegExp(r'[^a-zA-Z_]').hasMatch(name)) return null;
    final args = s.substring(open + 1, s.length - 1).trim();
    return _ParsedFn(name, args);
  }
}

/// Abstract predicate — single clause OR boolean combination.
abstract class _Predicate {
  bool matches(dynamic row);

  /// Top-level parse. Supports `&&` and `||` between simple clauses
  /// (left-to-right, no precedence beyond left-to-right). Parens not
  /// supported around boolean groups — keep predicates flat.
  static _Predicate? tryParse(String src) {
    final s = src.trim();
    if (s.isEmpty) return null;

    // Try `||` first so we honour OR-of-ANDs. Split top-level only —
    // since clauses don't contain && / || themselves (no nested
    // booleans), splitting on the literal token is safe.
    if (s.contains('||')) {
      final clauses = s.split('||').map((c) => tryParse(c)).toList();
      if (clauses.any((c) => c == null)) return null;
      return _Or(clauses.cast<_Predicate>());
    }
    if (s.contains('&&')) {
      final clauses = s.split('&&').map((c) => tryParse(c)).toList();
      if (clauses.any((c) => c == null)) return null;
      return _And(clauses.cast<_Predicate>());
    }
    return _Clause.tryParse(s);
  }
}

class _And extends _Predicate {
  final List<_Predicate> parts;
  _And(this.parts);
  @override
  bool matches(dynamic row) => parts.every((p) => p.matches(row));
}

class _Or extends _Predicate {
  final List<_Predicate> parts;
  _Or(this.parts);
  @override
  bool matches(dynamic row) => parts.any((p) => p.matches(row));
}

class _Clause extends _Predicate {
  final String field;
  final String op;
  final dynamic value;
  _Clause(this.field, this.op, this.value);

  static _Clause? tryParse(String src) {
    final s = src.trim();
    if (s.isEmpty) return null;

    // status in ('a','b')  — handle 'in' first, otherwise the != regex
    // below would eat the closing parens.
    final inMatch = RegExp(r"^([\w_]+)\s+in\s*\(([^)]*)\)$").firstMatch(s);
    if (inMatch != null) {
      final vals = inMatch.group(2)!.split(',').map((t) {
        final v = t.trim();
        if (v.startsWith("'") && v.endsWith("'")) return v.substring(1, v.length - 1);
        return v;
      }).toSet();
      return _Clause(inMatch.group(1)!, 'in', vals);
    }

    // status == 'X', status != 'X', score >= 5, etc.
    final cmp = RegExp(r"""^([\w_]+)\s*(==|!=|>=|<=|>|<)\s*('([^']*)'|"([^"]*)"|([\d.]+))$""")
        .firstMatch(s);
    if (cmp != null) {
      final field = cmp.group(1)!;
      final op = cmp.group(2)!;
      final literal = cmp.group(4) ?? cmp.group(5) ?? cmp.group(6);
      final num? asNum = literal == null ? null : num.tryParse(literal);
      return _Clause(field, op, asNum ?? literal);
    }

    return null;
  }

  @override
  bool matches(dynamic row) {
    final v = row is Map ? row[field] : null;
    switch (op) {
      case '==':
        return _eq(v, value);
      case '!=':
        return !_eq(v, value);
      case 'in':
        if (value is Set) return value.contains('$v');
        return false;
      case '>':
      case '>=':
      case '<':
      case '<=':
        if (v is! num || value is! num) return false;
        return switch (op) {
          '>' => v > value,
          '>=' => v >= value,
          '<' => v < value,
          '<=' => v <= value,
          _ => false,
        };
      default:
        return false;
    }
  }

  static bool _eq(dynamic a, dynamic b) {
    if (a is num && b is num) return a == b;
    return '$a' == '$b';
  }
}
