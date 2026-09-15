// File upload element. Two modes:
//
//  1. **Form-value mode** (legacy / default): when no `uploadEndpoint` is
//     configured, behaves as a non-interactive drop-zone widget — emits a
//     visual placeholder; the picked filename is stashed on local state.
//     Submission happens via the surrounding Form Block as part of a
//     normal form_submit action.
//
//  2. **Active-upload mode** (Phase F+1): when `uploadEndpoint` is set in
//     the element's config, picking files immediately POSTs each one as
//     multipart to that URL with the configured headers. Per-file
//     progress, success/error toast, and an event-bus emit so adjacent
//     vault browsers / data tables can refresh themselves via
//     `dataBinding.refreshOn`.
//
// All `{{...}}` tokens in `uploadEndpoint` / `uploadHeaders` are resolved
// against the page's `BindingContext` via `ExpressionResolver` — the same
// shape `dataBinding.url` uses on data widgets.
//
// Config shape (active mode):
//   {
//     "label": "Upload files",
//     "accept": "image/*,application/pdf",   // (optional) file picker filter
//     "multiple": true,                       // (optional) default false
//     "maxSizeMb": 50,                        // (optional) client-side guard
//     "uploadEndpoint": "{{env.X}}/projects/{{route.id}}/documents",
//     "uploadFieldName": "file",              // (optional) default "file"
//     "uploadHeaders": {                      // (optional)
//       "Authorization": "Bearer {{session.access_token}}"
//     },
//     "uploadExtraFields": {                  // (optional) extra form fields
//       "category": "media"
//     },
//     "uploadSuccessEvent": "file.uploaded"   // (optional) default "file.uploaded"
//   }

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../binding/expression_resolver.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../../../providers/page_context_provider.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';

class FileUploadElement extends ConsumerStatefulWidget {
  final PageElement element;
  final RenderMode mode;
  final String pageId;

  const FileUploadElement({
    super.key,
    required this.element,
    required this.mode,
    this.pageId = '',
  });

  @override
  ConsumerState<FileUploadElement> createState() => _FileUploadElementState();
}

class _UploadEntry {
  final String filename;
  double progress; // 0..1
  String? error;
  bool done;
  List<String> suggestedTags;

  _UploadEntry(this.filename)
      : progress = 0,
        error = null,
        done = false,
        suggestedTags = const [];
}

class _FileUploadElementState extends ConsumerState<FileUploadElement> {
  bool _hovering = false;
  final List<_UploadEntry> _entries = [];
  bool _picking = false;

  Map<String, dynamic> get _config => widget.element.config;

  bool get _activeMode =>
      (_config['uploadEndpoint'] as String?)?.isNotEmpty ?? false;

  Future<void> _pickAndUpload() async {
    if (_picking) return;
    final endpoint = _config['uploadEndpoint'] as String?;
    if (endpoint == null || endpoint.isEmpty) return;

    final multiple = _config['multiple'] as bool? ?? false;
    final acceptRaw = _config['accept'] as String? ?? '*';
    final maxSizeMb = (_config['maxSizeMb'] as num?)?.toInt() ?? 50;

    // file_picker takes a single broad `type` (or `allowedExtensions`), so it
    // can only narrow to ONE media class. Only do that when the accept asks for
    // exactly one (image-only / video-only / audio-only); for a mixed accept
    // like "image/*,video/*,audio/*" (or doc types it can't express) fall back
    // to `any` — otherwise the picker filters to just one class and a file of
    // another type (e.g. a photo when the filter ended up on video) can't be
    // selected, so the picker returns nothing and the upload silently no-ops.
    final wantsImage = acceptRaw.contains('image/');
    final wantsVideo = acceptRaw.contains('video/');
    final wantsAudio = acceptRaw.contains('audio/');
    final mediaClasses = [wantsImage, wantsVideo, wantsAudio].where((b) => b).length;
    FileType pickerType = FileType.any;
    if (mediaClasses == 1) {
      if (wantsImage) {
        pickerType = FileType.image;
      } else if (wantsVideo) {
        pickerType = FileType.video;
      } else {
        pickerType = FileType.audio;
      }
    }

    setState(() => _picking = true);
    FilePickerResult? picked;
    try {
      try {
        picked = await FilePicker.platform.pickFiles(
          allowMultiple: multiple,
          type: pickerType,
          withData: true, // load bytes so Flutter Web works without a real fs path
        );
      } catch (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[fileUpload] pickFiles threw: $e\n$st');
        }
        _toast('Could not open file picker: $e');
        return;
      }
      if (picked == null || picked.files.isEmpty) return;

      // Resolve the endpoint + headers once per pick (shared across all
      // selected files).
      final ctxMap = ref.read(bindingContextProvider);
      final ctx = ctxMap[widget.pageId];
      if (ctx == null) {
        _toast('Upload context unavailable.');
        return;
      }
      final resolver = ExpressionResolver(ctx);
      final resolvedEndpoint = await resolver.resolve(endpoint);
      final headers = <String, String>{};
      final rawHeaders = (_config['uploadHeaders'] as Map?) ?? const {};
      for (final entry in rawHeaders.entries) {
        final v = await resolver.resolve('${entry.value}');
        if (v.isNotEmpty) headers['${entry.key}'] = v;
      }
      final extraFields = <String, String>{};
      final rawExtra = (_config['uploadExtraFields'] as Map?) ?? const {};
      for (final entry in rawExtra.entries) {
        final v = await resolver.resolve('${entry.value}');
        extraFields['${entry.key}'] = v;
      }
      final fieldName = _config['uploadFieldName'] as String? ?? 'file';
      final successEvent =
          _config['uploadSuccessEvent'] as String? ?? 'file.uploaded';

      for (final f in picked.files) {
        if (f.bytes == null) {
          _toast('Could not read ${f.name}.');
          continue;
        }
        if (maxSizeMb > 0 && f.size > maxSizeMb * 1024 * 1024) {
          _toast('${f.name}: exceeds ${maxSizeMb}MB.');
          continue;
        }
        final entry = _UploadEntry(f.name);
        setState(() => _entries.add(entry));
        await _uploadOne(
          endpoint: resolvedEndpoint,
          headers: headers,
          extraFields: extraFields,
          fieldName: fieldName,
          successEvent: successEvent,
          entry: entry,
          bytes: f.bytes!,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _uploadOne({
    required String endpoint,
    required Map<String, String> headers,
    required Map<String, String> extraFields,
    required String fieldName,
    required String successEvent,
    required _UploadEntry entry,
    required List<int> bytes,
  }) async {
    final dio = Dio();
    final form = FormData.fromMap({
      ...extraFields,
      fieldName: MultipartFile.fromBytes(bytes, filename: entry.filename),
    });
    try {
      final response = await dio.post<dynamic>(
        endpoint,
        data: form,
        options: Options(headers: headers),
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => entry.progress = sent / total);
        },
      );
      if (!mounted) return;
      final body = response.data;
      final suggested = (body is Map && body['suggested_tags'] is List)
          ? List<String>.from(
              (body['suggested_tags'] as List).whereType<String>(),
            )
          : const <String>[];
      setState(() {
        entry.done = true;
        entry.progress = 1.0;
        entry.suggestedTags = suggested;
      });
      // Tell the rest of the page (vault browser, data table) to refresh.
      final ctx = ref.read(bindingContextProvider)[widget.pageId];
      ctx?.eventBus.publish(successEvent);
      _toast('Uploaded ${entry.filename}');
    } catch (e) {
      String detail = '$e';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map && body['detail'] != null) {
          detail = '${body['detail']}';
        } else if (e.message != null) {
          detail = e.message!;
        }
      }
      if (!mounted) return;
      setState(() => entry.error = detail);
      _toast('Upload failed: $detail');
    }
  }

  void _toast(String msg) {
    // The registry stores callbacks as `Object` to avoid a circular import
    // from providers/ back into widgets/. Cast through dynamic for the
    // optional onShowToast invocation; no-op if absent.
    final entry = ref.read(pageRendererCallbacksProvider)[widget.pageId];
    if (entry == null) return;
    try {
      // ignore: avoid_dynamic_calls
      (entry as dynamic).onShowToast?.call(msg);
    } catch (_) {/* registered shape doesn't match — silently ignore */}
  }

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final label = _config['label'] as String? ?? 'Upload files';
    final accept = _config['accept'] as String? ?? '*';
    final maxSizeMb = (_config['maxSizeMb'] as num?)?.toInt() ?? 50;
    final multiple = _config['multiple'] as bool? ?? false;
    final dropZone = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: _activeMode
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _activeMode ? _pickAndUpload : null,
        child: AnimatedContainer(
          width: double.infinity,
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(OTokens.s6),
          decoration: BoxDecoration(
            color: _hovering
                ? pal.primaryBlue.withValues(alpha: 0.06)
                : pal.bgSurface,
            borderRadius: BorderRadius.circular(OTokens.radiusMd),
            border: Border.all(
              color: _hovering
                  ? pal.primaryBlue.withValues(alpha: 0.5)
                  : pal.borderSubtle,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pal.accentCyan.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: _picking
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(LucideIcons.upload,
                        size: 20, color: pal.accentCyan),
              ),
              const SizedBox(height: OTokens.s3),
              Text(
                _activeMode
                    ? (_picking ? 'Opening picker…' : 'Click to choose files')
                    : 'Click or drag files here',
                style: GoogleFonts.inter(
                  fontSize: OTokens.textSm,
                  fontWeight: FontWeight.w500,
                  color: pal.textSecondary,
                ),
              ),
              const SizedBox(height: OTokens.s1),
              Text(
                '${multiple ? "Multiple files" : "Single file"} · '
                'Max ${maxSizeMb}MB · '
                '${accept == "*" ? "Any format" : accept}',
                style: GoogleFonts.inter(
                  fontSize: OTokens.textXs,
                  color: pal.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return FormFieldShell(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          dropZone,
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: OTokens.s3),
            for (final e in _entries) _UploadRow(entry: e),
          ],
        ],
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final _UploadEntry entry;
  const _UploadRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final pal = OPaletteScope.of(context);
    final Color color;
    final IconData icon;
    if (entry.error != null) {
      color = const Color(0xFFB91C1C);
      icon = LucideIcons.alertCircle;
    } else if (entry.done) {
      color = pal.gainGreen;
      icon = LucideIcons.checkCircle2;
    } else {
      color = pal.primaryBlue;
      icon = LucideIcons.uploadCloud;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.filename,
                  style: GoogleFonts.inter(
                    fontSize: OTokens.textXs,
                    color: pal.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!entry.done && entry.error == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: entry.progress.clamp(0.0, 1.0),
                      minHeight: 3,
                    ),
                  ),
                if (entry.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.error!,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                if (entry.done && entry.suggestedTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 2, top: 2),
                          child: Text(
                            'Tagged:',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: pal.textMuted,
                            ),
                          ),
                        ),
                        for (final tag in entry.suggestedTags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: pal.accentCyan.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: pal.accentCyan
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              tag,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: pal.accentCyan,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
