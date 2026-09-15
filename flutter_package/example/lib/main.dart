/// Example: embedding Mit Stack into a separate Flutter app.
///
/// In your host app's pubspec.yaml:
///
/// ```yaml
/// dependencies:
///   flutter:
///     sdk: flutter
///   flutter_riverpod: ^2.5.1
///   mit_stack:
///     path: ../../frontend     # adjust path to your checkout
/// ```
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mit_stack/mit_stack_app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MitStackApp(
        config: MitStackConfig(
          // Point to your deployed API
          apiBaseUrl: 'https://api.mycompany.com',
          appName: 'Acme Automation',

          // Disable builder tools for mobile-only deployments:
          // enableWorkflowBuilder: false,
          // enableFormBuilder: false,

          // Custom mobile breakpoint (default 768):
          // mobileBreakpoint: 600,
        ),
      ),
    ),
  );
}
