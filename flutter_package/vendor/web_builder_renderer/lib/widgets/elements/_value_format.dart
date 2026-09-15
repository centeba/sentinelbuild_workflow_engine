// Small display-value formatters shared by element widgets. Kept dependency-
// free (no intl) so the renderer package stays light.

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Format an ISO-8601 date/datetime string as a friendly date (e.g.
/// `2026-06-06T00:00:00Z` → `Jun 6, 2026`). Non-date input is returned as-is.
String friendlyDate(String raw) {
  final d = DateTime.tryParse(raw.trim());
  if (d == null) return raw;
  final local = d.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

// Matches an ISO-8601 date or datetime embedded in free text.
final RegExp _isoDateTime =
    RegExp(r'\d{4}-\d{2}-\d{2}(?:[T ][0-9:.+\-Z]*)?');

/// Replace any ISO date/datetime substrings inside [text] with a friendly date.
/// Leaves the rest of the string untouched. Used so resolved templates like
/// "… · DOL 2026-06-06T00:00:00Z" render "… · DOL Jun 6, 2026".
String formatIsoDatesIn(String text) =>
    text.replaceAllMapped(_isoDateTime, (m) => friendlyDate(m.group(0)!));
