// Web implementation of the browser download. Only compiled on web via the
// conditional import in workflow_builder_screen.dart, so ``dart:html`` is safe
// here (it never reaches the non-web/test build). dart:html is deprecated in
// favour of package:web, but the blob/anchor download pattern has no stable
// package:web equivalent yet, so keep it and suppress the notice here.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

void downloadText(
  String content,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
