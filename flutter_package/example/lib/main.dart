/// Example host app: composes the mit_stack screens into a navigable app.
///
/// The package ships individual screens; a real host wires them into its own
/// navigation. This example wires a go_router with a nav rail so every screen —
/// including the **workflow builder** (via Workflows → New / Edit) — is reachable.
///
/// Point the API base URL with `--dart-define=API_BASE_URL=/api/v1` (the Docker
/// image does this; nginx proxies /api to the backend).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mit_stack/mit_stack.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the bundled English strings before the first frame so labels render.
  await Translations.instance.ensureLoaded();
  runApp(
    ProviderScope(
      // Riverpod 3 auto-retries any throwing provider forever (exponential
      // backoff, no limit). A terminal error — e.g. a 401 when unauthenticated
      // — would then become an unbounded request storm. Screens here refresh
      // explicitly, so disable auto-retry and let failures surface.
      retry: (_, __) => null,
      child: const ExampleApp(),
    ),
  );
}

final _router = GoRouter(
  initialLocation: '/workflows',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _Shell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/workflows', builder: (_, __) => const WorkflowsScreen()),
        // Workflow builder — reached from WorkflowsScreen's New / Edit actions.
        GoRoute(
          path: '/workflows/new',
          builder: (_, __) => const WorkflowBuilderScreen(workflowId: null),
        ),
        GoRoute(
          path: '/workflows/:id/edit',
          builder: (_, state) => WorkflowBuilderScreen(workflowId: state.pathParameters['id']),
        ),
        GoRoute(path: '/rules', builder: (_, __) => const RulesScreen()),
        GoRoute(path: '/recipes', builder: (_, __) => const RecipeBuilderScreen()),
        GoRoute(path: '/integrations', builder: (_, __) => const IntegrationsScreen()),
      ],
    ),
  ],
);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Workflow Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      routerConfig: _router,
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.location});

  final Widget child;
  final String location;

  static const List<(String, IconData, String)> _dests = [
    ('/workflows', Icons.account_tree_outlined, 'Workflows'),
    ('/rules', Icons.rule_outlined, 'Rules'),
    ('/recipes', Icons.receipt_long_outlined, 'Recipes'),
    ('/integrations', Icons.extension_outlined, 'Integrations'),
  ];

  int get _selectedIndex {
    final i = _dests.indexWhere((d) => location.startsWith(d.$1));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => context.go(_dests[i].$1),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _dests)
                NavigationRailDestination(icon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
