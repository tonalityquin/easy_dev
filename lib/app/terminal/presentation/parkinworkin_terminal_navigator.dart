import 'package:flutter/material.dart';

import '../application/parkinworkin_terminal_diagnostics.dart';
import 'parkinworkin_terminal_screen.dart';

Future<void> showParkinWorkinTerminal(
  BuildContext context, {
  String source = 'command_launcher',
}) async {
  if (!context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final routeName =
      '/parkinworkin_terminal/${Uri.encodeComponent(source)}';
  ParkinWorkinTerminalDiagnostics.record(
    'terminal_open_requested',
    context: source,
    meta: <String, Object?>{
      'route': routeName,
    },
  );
  try {
    await navigator.push<void>(
      PageRouteBuilder<void>(
        settings: RouteSettings(name: routeName),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ParkinWorkinTerminalScreen.workspace(source: source);
        },
      ),
    );
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_route_closed',
      context: source,
      meta: <String, Object?>{
        'route': routeName,
      },
    );
  } catch (error) {
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_route_push_failed',
      context: source,
      meta: <String, Object?>{
        'route': routeName,
        'errorType': error.runtimeType,
      },
    );
    rethrow;
  }
}
