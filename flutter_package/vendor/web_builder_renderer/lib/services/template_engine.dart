class TemplateEngine {
  static final _tokenRegex = RegExp(r'\{\{([^}]+)\}\}');

  String resolve(
    String template, {
    Map<String, dynamic> context = const {},
    Map<String, dynamic> pageFormResults = const {},
    Map<String, dynamic> siteGlobals = const {},
    Map<String, dynamic> elementValues = const {},
  }) {
    return template.replaceAllMapped(_tokenRegex, (match) {
      final path = match.group(1)!.trim();
      final resolved = _resolvePath(
        path,
        context: context,
        pageFormResults: pageFormResults,
        siteGlobals: siteGlobals,
        elementValues: elementValues,
      );
      return resolved?.toString() ?? match.group(0)!;
    });
  }

  dynamic resolveValue(
    String template, {
    Map<String, dynamic> context = const {},
    Map<String, dynamic> pageFormResults = const {},
    Map<String, dynamic> siteGlobals = const {},
    Map<String, dynamic> elementValues = const {},
  }) {
    final match = _tokenRegex.firstMatch(template.trim());
    if (match != null && match.group(0) == template.trim()) {
      final path = match.group(1)!.trim();
      return _resolvePath(
        path,
        context: context,
        pageFormResults: pageFormResults,
        siteGlobals: siteGlobals,
        elementValues: elementValues,
      );
    }
    return resolve(template,
        context: context,
        pageFormResults: pageFormResults,
        siteGlobals: siteGlobals,
        elementValues: elementValues);
  }

  dynamic _resolvePath(
    String path, {
    required Map<String, dynamic> context,
    required Map<String, dynamic> pageFormResults,
    required Map<String, dynamic> siteGlobals,
    required Map<String, dynamic> elementValues,
  }) {
    final parts = path.split('.');
    if (parts.isEmpty) return null;

    Map<String, dynamic>? root;
    List<String> remainingParts;

    if (parts[0] == 'context') {
      root = context;
      remainingParts = parts.sublist(1);
    } else if (parts[0] == 'page' && parts.length > 1 && parts[1] == 'formResult') {
      root = pageFormResults;
      remainingParts = parts.sublist(2);
    } else if (parts[0] == 'site') {
      root = siteGlobals;
      remainingParts = parts.sublist(1);
    } else if (parts[0] == 'element') {
      root = elementValues;
      remainingParts = parts.sublist(1);
    } else {
      // Direct key access in context
      root = context;
      remainingParts = parts;
    }

    dynamic current = root;
    for (final part in remainingParts) {
      if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }

  dynamic extractPath(dynamic data, String path) {
    if (path == r'$' || path.isEmpty) return data;

    var cleaned = path;
    if (cleaned.startsWith(r'$.')) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith(r'$')) {
      cleaned = cleaned.substring(1);
    }

    dynamic current = data;
    final parts = cleaned.split('.');
    for (final part in parts) {
      if (part.isEmpty) continue;
      final arrayMatch = RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(part);
      if (arrayMatch != null) {
        final key = arrayMatch.group(1)!;
        final idx = int.parse(arrayMatch.group(2)!);
        if (current is Map) {
          current = current[key];
        }
        if (current is List && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
      } else if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }
}
