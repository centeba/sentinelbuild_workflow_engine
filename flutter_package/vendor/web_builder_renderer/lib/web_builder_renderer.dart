/// Public surface of the web_builder runtime renderer.
///
/// Embed this package in any Flutter app to render `PageDefinition` JSON
/// authored in the web-builder. The renderer is mode-aware
/// (`RenderMode { builder, preview, published }`); the `builder` mode is
/// used by the authoring tool, the others by host apps.
library;

// Models
export 'models/page_definition.dart';
export 'models/page_section.dart';
export 'models/page_element.dart';
export 'models/site_definition.dart';
export 'models/site_theme.dart';
export 'models/element_style.dart';
export 'models/data_binding.dart';
export 'models/navigation_action.dart';
export 'models/responsive_override.dart';

// Element registry + rendering
export 'constants/element_registry.dart';
export 'widgets/elements/element_renderer.dart';

// Phase 4 — data-binding runtime
export 'binding/event_bus.dart';
export 'binding/data_source.dart';
export 'binding/expression_resolver.dart';
export 'binding/form_submit_action.dart';
// Phase 8 — real-time refresh hooks
export 'binding/realtime.dart';
export 'binding/bus_websocket_adapter.dart'
    show BusWebSocketAdapter, BusTokenProvider;
// Multi-lang integration — `{{i18n.<key>}}` token support
export 'binding/translator.dart';

// Services / runtime infra
export 'services/template_engine.dart';
export 'services/sentinelbuild_client.dart';
export 'services/sentinelbuild_settings.dart';
export 'services/site_storage_service.dart'
    show
        SiteStorage,
        LocalSiteStorage,
        RemoteSiteStorage,
        SiteStorageService,
        AuthTokenProvider,
        siteStorageProvider;

// Providers
export 'providers/page_context_provider.dart';
export 'providers/section_counts_provider.dart';
// NOTE: builder_provider is exported here for now because element widgets
// reference it for builder-mode interactions (selection, drop targets). Phase 3
// of the SentinelBuild migration plan introduces a `BuilderActionsService`
// abstraction so runtime-only consumers don't pull in builder state.
export 'providers/builder_provider.dart';

// Design system (host apps may want to read tokens directly)
// The generated token table. Exported because `OPaletteData.fromPd` takes a
// `PdPalette`, so a host app installing an OPaletteScope needs both.
export 'design/pd_tokens.gen.dart';
export 'design/palette.dart';
export 'design/tokens.dart';
export 'design/theme.dart';
export 'design/glass_card.dart';
export 'design/gradient_background.dart';

// Top-level renderer widget for host apps
export 'widgets/page_renderer_widget.dart';

// Drag data (used by builder mode + element drop targets)
export 'widgets/common/drag_data.dart';

// ─── Form builder ─────────────────────────────────────────────────────────────
// The standalone form builder was retired — forms are authored as pages in the
// web builder (the page-element form components in `widgets/elements/form/`).
// `builder_theme` + `builder_i18n` remain: they are the shared builder-canvas
// theme + translator hook the PAGE builder uses too (not form-specific).
export 'forms/builder_i18n.dart' show registerBuilderTranslator;
export 'forms/builder_theme.dart' show BuilderTheme;
