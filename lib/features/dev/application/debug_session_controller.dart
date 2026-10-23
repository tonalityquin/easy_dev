import 'package:flutter/material.dart';

import '../../../app/terminal/application/parkinworkin_terminal_diagnostics.dart';
import '../../selector/application/dev_auth.dart';
import 'developer_account_authorization.dart';
import 'developer_login_gate_service.dart';

class DebugSessionController {
  DebugSessionController._();

  static bool _initialized = false;

  static ValueNotifier<bool> get enabled => DevAuth.devModeEnabled;

  static Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await DevAuth.restorePrefs();
    _initialized = true;
    record(
      'debug_session_restore',
      source: 'app_start',
      meta: <String, Object?>{'active': prefs.devAuthorized},
    );
  }

  static Future<bool> enable({String source = 'terminal'}) async {
    if (!DeveloperAccountAuthorization.isAuthorized) {
      final alreadyEnabled = await DevAuth.isDevModeEnabled();
      if (alreadyEnabled) {
        await DevAuth.setDevModeEnabled(false);
      }
      record(
        'debug_session_enable_denied',
        source: source,
        meta: const <String, Object?>{
          'reason': 'developer_authorization_required',
        },
      );
      return false;
    }

    final gateAuthorized = await DeveloperLoginGateService.verify(
      source: 'debug_session_enable_$source',
    );
    if (!gateAuthorized) {
      final wasEnabled = await DevAuth.isDevModeEnabled();
      if (wasEnabled) {
        await DevAuth.setDevModeEnabled(false);
      }
      record(
        'debug_session_enable_denied',
        source: source,
        meta: const <String, Object?>{
          'reason': 'developer_server_gate_denied',
        },
      );
      return false;
    }

    final alreadyEnabled = await DevAuth.isDevModeEnabled();
    if (!alreadyEnabled) {
      await DevAuth.setDevModeEnabled(true);
    }
    record(
      'debug_session_enable',
      source: source,
      meta: <String, Object?>{
        'alreadyEnabled': alreadyEnabled,
        'authorization': 'developer_account',
      },
    );
    return true;
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
    DeveloperAccountAuthorization.clearSession(source: source);
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
