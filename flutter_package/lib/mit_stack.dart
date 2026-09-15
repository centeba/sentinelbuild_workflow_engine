/// Public surface of the Mit Stack package, intended for host
/// applications (e.g. SentinelBuild) that embed individual screens.
///
/// **This package is library-only.** It does not ship a standalone
/// app entry point. The host owns ``main.dart`` and routing; this
/// package exposes screens + Riverpod providers the host can wire
/// into its own ``ProviderScope``.
///
/// ## Wiring inside a host
///
/// Screens read API config from ``dioProvider``. Override it in the
/// host's ``ProviderScope`` so calls go through the host's reverse
/// proxy and auth interceptor:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     dioProvider.overrideWith((ref) {
///       final dio = Dio(BaseOptions(baseUrl: '/api/mit-stack/v1'));
///       dio.interceptors.add(/* host auth interceptor */);
///       return dio;
///     }),
///     aiAdminDioProvider.overrideWith((ref) {
///       // similar override pointing at the integration-hub prefix
///     }),
///   ],
///   child: const HostApp(),
/// )
/// ```
///
/// ## What's exported
///
/// Only the screens + providers that SentinelBuild actually consumes.
/// New screens added to the package stay invisible to the host until
/// they're explicitly listed here — every re-export pulls more code
/// into the host's compile graph.
library mit_stack;

// API clients — host overrides these to inject baseUrl + auth.
export 'services/api_client.dart' show dioProvider;
// ``aiAdminApiProvider`` is also exported because internal Mit Stack
// screens (workflow_builder/node_palette etc) import it through the
// barrel to fetch the registry list. They could use a relative
// import; keeping it in the barrel for now avoids a fan-out edit.
export 'screens/ai_admin/ai_admin_api.dart'
    show aiAdminDioProvider, aiAdminApiProvider;

// Embedded screens (alphabetical).
export 'screens/ai_admin/ai_admin_screen.dart' show AiAdminScreen;
// Embeddable multi-model chat panel — host injects its Dio clients (+ optional
// i18n and file-picker). Used by the chassis Chat screen and domain apps.
export 'widgets/chat/chat_api.dart' show ChatApi, PickedFile;
export 'widgets/chat/embedded_chat.dart' show EmbeddedChat;
// The standalone form builder was retired (forms are authored as pages in the
// Web Builder). Only the shared builder-canvas theme + translator hook remain.
export 'package:web_builder_renderer/web_builder_renderer.dart'
    show
        BuilderTheme,
        registerBuilderTranslator;
export 'screens/rules/rules_screen.dart' show RulesScreen;
export 'screens/settings/settings_screen.dart' show SettingsScreen;
export 'screens/workflow_builder/workflow_builder_screen.dart'
    show WorkflowBuilderScreen;
export 'screens/workflows/workflows_screen.dart' show WorkflowsScreen;
export 'screens/recipe_builder/recipe_builder_screen.dart'
    show RecipeBuilderScreen;
