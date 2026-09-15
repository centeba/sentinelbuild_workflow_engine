// Non-web stub. ``dart:html`` is unavailable off the web platform (and in the
// Flutter test VM), so importing it unconditionally fails to compile. The
// conditional import in workflow_builder_screen.dart selects this stub
// everywhere except web; callers wrap it in try/catch and fall back to showing
// the content in a dialog.
void downloadText(
  String content,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('Browser download is only available on the web.');
}
