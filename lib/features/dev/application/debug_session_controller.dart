import 'package:flutter/material.dart';

import '../../../app/terminal/application/parkinworkin_terminal_diagnostics.dart';
import '../../selector/application/dev_auth.dart';

class DebugSessionController {
  DebugSessionController._();

  static ValueNotifier<bool> get enabled => DevAuth.devModeEnabled;

  static Future<void> initialize() async {
    final prefs = await DevAuth.restorePrefs();
    record(
      'debug_session_restore',
      source: 'app_start',
      meta: <String, Object?>{'active': prefs.devAuthorized},
    );
  }

  static Future<void> enable({String source = 'terminal'}) async {
    final alreadyEnabled = await DevAuth.isDevModeEnabled();
    if (!alreadyEnabled) {
      await DevAuth.setDevModeEnabled(true);
    }
    record(
      'debug_session_enable',
      source: source,
      meta: <String, Object?>{'alreadyEnabled': alreadyEnabled},
    );
  }

  static Future<void> disable({String source = 'developer_tools'}) async {
    final wasEnabled = await DevAuth.isDevModeEnabled();
    record(
      'debug_session_disable',
      source: source,
      meta: <String, Object?>{'wasEnabled': wasEnabled},
    );
    if (wasEnabled) {
      await DevAuth.setDevModeEnabled(false);
    }
  }

  static void record(
    String event, {
    required String source,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    ParkinWorkinTerminalDiagnostics.record(
      event,
      context: source,
      meta: meta,
    );
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String source,
    required String description,
  }) async {
    record(
      'debug_tool_status_open',
      source: source,
      meta: <String, Object?>{'descriptionLength': description.length},
    );
    await ParkinWorkinTerminalDiagnostics.showStatus(
      context,
      terminalContext: source,
      description: description,
    );
  }
}
