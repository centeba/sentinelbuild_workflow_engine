/// Example: embedding a Mit Stack screen into a Flutter app.
///
/// The package exposes individual screens (WorkflowsScreen, RulesScreen,
/// SettingsScreen, WorkflowBuilderScreen, AiAdminScreen, …) rather than a single
/// wrapper widget, so a host app composes them into its own navigation. Point
/// the API base URL with `--dart-define=API_BASE_URL=https://api.example.com`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mit_stack/mit_stack.dart';

void main() {
  runApp(const ProviderScope(child: ExampleApp()));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workflow Engine',
      debugShowCheckedModeBanner: false,
      home: const WorkflowsScreen(),
    );
  }
}
