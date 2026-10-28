import '../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../app/terminal/application/parkinworkin_terminal_diagnostics.dart';
import '../../../app/utils/access_gate_diagnostics.dart';
import '../../launcher/application/launcher_diagnostics.dart';
import 'developer_account_authorization.dart';
import 'login_gate_paths.dart';

class DeveloperLoginGateService {
  DeveloperLoginGateService._();

  static const String documentPath = LoginGatePaths.developer;

  static Future<bool> verify({required String source}) async {
    if (kDebugMode) {
      _record('debug_bypass', source: source);
      return true;
    }

    if (!DeveloperAccountAuthorization.isAuthorized) {
      _record('denied', source: source, reason: 'identity_not_authorized');
      DeveloperAccountAuthorization.clearSession(source: source);
      return false;
    }

    _record('started', source: source);
    try {
      final document = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => FirebaseFirestore.instance
          .doc(documentPath)
          .get(const GetOptions(source: Source.server)), source: 'developer_login_gate_service.get');
      final approved = document.exists &&
          document.data()?['enabled'] == true &&
          DeveloperAccountAuthorization.isAuthorized;
      if (!approved) {
        _record('denied', source: source, reason: 'server_not_enabled');
        DeveloperAccountAuthorization.clearSession(source: source);
        return false;
      }
      _record('verified', source: source);
      return true;
    } catch (error) {
      _record('failed', source: source, reason: error.runtimeType.toString());
      DeveloperAccountAuthorization.clearSession(source: source);
      return false;
    }
  }

  static void _record(
    String outcome, {
    required String source,
    String? reason,
  }) {
    final meta = <String, Object?>{
      'source': source,
      if (reason != null) 'reason': reason,
    };
    AccessGateDiagnostics.record(
      'developer_login_server_gate_$outcome',
      source: source,
      group: 'developer',
      reason: reason ?? documentPath,
    );
    LauncherDiagnostics.record(
      'developer_login_server_gate_$outcome',
      scope: source,
      meta: meta,
    );
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_developer_login_server_gate_$outcome',
      context: source,
      meta: meta,
    );
  }
}
