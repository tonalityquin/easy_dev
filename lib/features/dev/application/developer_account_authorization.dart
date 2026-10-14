import 'package:flutter/foundation.dart';

import '../../../app/auth/google_auth_session.dart';
import '../../../app/terminal/application/parkinworkin_terminal_diagnostics.dart';

class DeveloperAccountAuthorization {
  DeveloperAccountAuthorization._();

  static const Set<String> allowedEmails = <String>{
    'surge1868@gmail.com',
    'qperfectusofficial@gmail.com',
  };

  static bool _releaseSessionAuthorized = false;
  static String? _authorizedEmail;

  static bool get isAuthorized => kDebugMode || _releaseSessionAuthorized;
  static String? get authorizedEmail => _authorizedEmail;

  static Future<bool> authorizeInteractive({
    String source = 'developer_authorization',
  }) async {
    if (kDebugMode) {
      _record(
        'developer_authorization_allowed',
        source: source,
        meta: const <String, Object?>{
          'mode': 'debug',
          'interactiveGoogle': false,
        },
      );
      return true;
    }

    _releaseSessionAuthorized = false;
    _authorizedEmail = null;
    _record(
      'developer_authorization_start',
      source: source,
      meta: const <String, Object?>{
        'mode': 'release',
        'interactiveGoogle': true,
      },
    );

    try {
      final identity = await GoogleAuthSession.instance.authenticateIdentityOnly(
        forceAccountSelection: true,
      );
      final email = identity.normalizedEmail;
      final allowed = allowedEmails.contains(email);
      if (!allowed) {
        _record(
          'developer_authorization_denied',
          source: source,
          meta: const <String, Object?>{
            'mode': 'release',
            'reason': 'google_account_not_allowed',
          },
        );
        return false;
      }

      _releaseSessionAuthorized = true;
      _authorizedEmail = email;
      _record(
        'developer_authorization_allowed',
        source: source,
        meta: const <String, Object?>{
          'mode': 'release',
          'interactiveGoogle': true,
        },
      );
      return true;
    } catch (error) {
      _releaseSessionAuthorized = false;
      _authorizedEmail = null;
      _record(
        'developer_authorization_failed',
        source: source,
        meta: <String, Object?>{
          'mode': 'release',
          'errorType': error.runtimeType.toString(),
        },
      );
      return false;
    }
  }

  static void clearSession({String source = 'developer_authorization'}) {
    final hadSession = _releaseSessionAuthorized || _authorizedEmail != null;
    _releaseSessionAuthorized = false;
    _authorizedEmail = null;
    if (hadSession) {
      _record(
        'developer_authorization_cleared',
        source: source,
        meta: const <String, Object?>{'mode': 'release'},
      );
    }
  }

  static void _record(
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
}
