import 'element_style.dart';
import 'data_binding.dart';
import 'navigation_action.dart';
import 'responsive_override.dart';

enum PageElementType {
  // Layout
  container,
  row,
  columns,
  stack,
  divider,
  spacer,
  // Content
  text,
  heading,
  image,
  icon,
  badge,
  // Interactive
  button,
  link,
  navTabs,
  // Data
  statCard,
  dataTable,
  chart,
  list,
  apiText,
  // Advanced data viz
  gaugeChart,
  ganttChart,
  kanban,
  heatmap,
  waterfallChart,
  candlestick,
  sparkline,
  // Layout extras
  card,
  accordion,
  contentTabs,
  callout,
  // Content extras
  bulletList,
  orderedList,
  blockquote,
  richText,
  video,
  // Interactive extras
  progressBar,
  stepper,
  breadcrumbs,
  timeline,
  // Form
  form,
  textField,
  textArea,
  emailField,
  phoneField,
  numberField,
  dropdown,
  checkbox,
  checkboxGroup,
  radioGroup,
  datePicker,
  fileUpload,
  signaturePad,
  formSubmitButton,
  // Form (legacy names kept for compatibility)
  selectField,
  checkboxField,
  switchField,
  rangeSlider,
  multiSelect,
  tagsInput,
  searchField,
  passwordField,
  /// Phase 5 anti-abuse: hidden honeypot field. Renders as a visually
  /// off-screen input that legitimate users won't fill but bots will. The
  /// public-submit endpoint silently accepts (without dispatching) any
  /// submission whose `_hp` value is non-empty.
  honeypot,
  // Form parity with mit_stack form_builder's `kFieldTypes`.
  // Suffixes (`Field`) added on `url`/`time`/`dateTime`/`hidden` to
  // avoid clashes with Dart core types and existing identifiers.
  currency,
  urlField,
  timeField,
  dateTimeField,
  rating,
  hiddenField,
  dataGrid,
  computed,
  // SentinelBuild
  vaultBrowser,
  envelopeStatus,
  signingCeremony,
  workflowStatus,
  agentChat,
  // Restoration: division-aware sub-job workspace (templated phase tracker +
  // checklists + notes + documentation), persisted to the sub-job.
  workspacePanel,
  // Restoration: thumbnail grid of media (photos) for a project/sub-job;
  // fetches each image's bytes with the auth header and renders in-memory.
  mediaGallery,
  // Restoration: compliance/submission readiness panel — fetches the effective
  // (carrier+TPA+contractor) requirements and flags missing docs/photos/tasks.
  readinessPanel,
  // Restoration: live presence (CON-14) — heartbeats the current user and
  // shows who else is on the same sub-job (viewing/editing).
  presencePanel,
  // Restoration: contractor performance scorecard (CON-26) — metric tiles.
  scorecardPanel,
  // Restoration: labor clock in/out + ready-to-invoice gate (CON-23/24/25).
  laborInvoicePanel,
}

class PageElement {
  final String id;
  final PageElementType type;
  final String? sectionId;
  final int rowIndex;
  final int colWidth;
  final Map<String, dynamic> config;
  final ElementStyle? style;
  final DataBinding? dataBinding;
  final Map<String, dynamic>? conditional;
  final Map<String, ResponsiveOverride> responsive;
  final List<PageElement>? children;
  final NavigationAction? action;
  /// Phase 6 of documents/platform/web-builder-roadmap.md — element-level role filter.
  /// Null or empty = visible to all authenticated users. When non-empty, the
  /// element renders only if `PageContext.roles` intersects this list.
  final List<String>? roleVisibility;

  const PageElement({
    required this.id,
    required this.type,
    this.sectionId,
    this.rowIndex = 0,
    this.colWidth = 12,
    this.config = const {},
    this.style,
    this.dataBinding,
    this.conditional,
    this.responsive = const {},
    this.children,
    this.action,
    this.roleVisibility,
  });

  PageElement copyWith({
    String? id,
    PageElementType? type,
    Object? sectionId = _sentinel,
    int? rowIndex,
    int? colWidth,
    Map<String, dynamic>? config,
    Object? style = _sentinel,
    Object? dataBinding = _sentinel,
    Object? conditional = _sentinel,
    Map<String, ResponsiveOverride>? responsive,
    Object? children = _sentinel,
    Object? action = _sentinel,
    Object? roleVisibility = _sentinel,
  }) {
    return PageElement(
      id: id ?? this.id,
      type: type ?? this.type,
      sectionId: identical(sectionId, _sentinel)
          ? this.sectionId
          : sectionId as String?,
      rowIndex: rowIndex ?? this.rowIndex,
      colWidth: colWidth ?? this.colWidth,
      config: config ?? this.config,
      style: identical(style, _sentinel)
          ? this.style
          : style as ElementStyle?,
      dataBinding: identical(dataBinding, _sentinel)
          ? this.dataBinding
          : dataBinding as DataBinding?,
      conditional: identical(conditional, _sentinel)
          ? this.conditional
          : conditional as Map<String, dynamic>?,
      responsive: responsive ?? this.responsive,
      children: identical(children, _sentinel)
          ? this.children
          : children as List<PageElement>?,
      action: identical(action, _sentinel)
          ? this.action
          : action as NavigationAction?,
      roleVisibility: identical(roleVisibility, _sentinel)
          ? this.roleVisibility
          : roleVisibility as List<String>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (sectionId != null) 'sectionId': sectionId,
        'rowIndex': rowIndex,
        'colWidth': colWidth,
        if (config.isNotEmpty) 'config': config,
        if (style != null) 'style': style!.toJson(),
        if (dataBinding != null) 'dataBinding': dataBinding!.toJson(),
        if (conditional != null) 'conditional': conditional,
        if (responsive.isNotEmpty)
          'responsive':
              responsive.map((k, v) => MapEntry(k, v.toJson())),
        if (children != null)
          'children': children!.map((c) => c.toJson()).toList(),
        if (action != null) 'action': action!.toJson(),
        if (roleVisibility != null && roleVisibility!.isNotEmpty)
          'roleVisibility': roleVisibility,
      };

  factory PageElement.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = PageElementType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => PageElementType.text,
    );

    // Preserve the raw action map under `config._rawAction` when it's a
    // Phase-4 form_submit shape (`{type: 'form_submit', method, url,
    // body, headers, onSuccess, onError}`) so the Form Block can read
    // the full payload — NavigationAction.fromJson only keeps
    // `targetPageId / type / params`.
    final config = Map<String, dynamic>.from(json['config'] as Map? ?? {});
    final rawAction = json['action'];
    if (rawAction is Map<String, dynamic> &&
        rawAction['type'] == 'form_submit' &&
        !config.containsKey('_rawAction')) {
      config['_rawAction'] = rawAction;
    }

    return PageElement(
      id: json['id'] as String,
      type: type,
      sectionId: json['sectionId'] as String?,
      rowIndex: json['rowIndex'] as int? ?? 0,
      colWidth: json['colWidth'] as int? ?? 12,
      config: config,
      style: json['style'] != null
          ? ElementStyle.fromJson(json['style'] as Map<String, dynamic>)
          : null,
      dataBinding: json['dataBinding'] != null
          ? DataBinding.fromJson(
              json['dataBinding'] as Map<String, dynamic>)
          : null,
      conditional: json['conditional'] != null
          ? Map<String, dynamic>.from(
              json['conditional'] as Map<String, dynamic>)
          : null,
      responsive:
          (json['responsive'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(
            k, ResponsiveOverride.fromJson(v as Map<String, dynamic>)),
      ),
      children: (json['children'] as List<dynamic>?)
          ?.map((c) => PageElement.fromJson(c as Map<String, dynamic>))
          .toList(),
      action: json['action'] != null
          ? NavigationAction.fromJson(
              json['action'] as Map<String, dynamic>)
          : null,
      roleVisibility: (json['roleVisibility'] ?? json['role_visibility']) is List
          ? List<String>.from(
              (json['roleVisibility'] ?? json['role_visibility']) as List)
          : null,
    );
  }
}

const _sentinel = Object();
