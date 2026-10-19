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
  static String? _lastAuthorizationStateKey;

  static bool get isAuthorized {
    if (kDebugMode) {
      _recordAuthorizationStateIfChanged(
        authorized: true,
        mode: 'debug',
        releaseSessionAuthorized: _releaseSessionAuthorized,
        currentIdentityPresent:
            GoogleAuthSession.instance.currentIdentity != null,
        authorizedEmailPresent: _authorizedEmail != null,
        emailMatches: true,
        currentEmailAllowed: true,
      );
      return true;
    }

    final currentEmail =
        GoogleAuthSession.instance.currentIdentity?.normalizedEmail;
    final authorizedEmail = _authorizedEmail?.trim().toLowerCase();
    final currentIdentityPresent = currentEmail != null;
    final authorizedEmailPresent = authorizedEmail != null;
    final emailMatches = currentIdentityPresent &&
        authorizedEmailPresent &&
        currentEmail == authorizedEmail;
    final currentEmailAllowed =
        currentEmail != null && allowedEmails.contains(currentEmail);
    final authorized = _releaseSessionAuthorized &&
        emailMatches &&
        currentEmailAllowed;

    _recordAuthorizationStateIfChanged(
      authorized: authorized,
      mode: 'release',
      releaseSessionAuthorized: _releaseSessionAuthorized,
      currentIdentityPresent: currentIdentityPresent,
      authorizedEmailPresent: authorizedEmailPresent,
      emailMatches: emailMatches,
      currentEmailAllowed: currentEmailAllowed,
    );

    return authorized;
  }

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
          'firebaseBridgeVerified': false,
          'debugBypass': true,
        },
      );
      return true;
    }

    _releaseSessionAuthorized = false;
    _authorizedEmail = null;
    _lastAuthorizationStateKey = null;
    _record(
      'developer_authorization_start',
      source: source,
      meta: const <String, Object?>{
        'mode': 'release',
        'interactiveGoogle': true,
      },
    );

    try {
      final identity = await GoogleAuthSession.instance
          .ensureFirebaseAuthenticatedIdentity(
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
      _lastAuthorizationStateKey = null;
      final authorized = isAuthorized;
      if (!authorized) {
        _releaseSessionAuthorized = false;
        _authorizedEmail = null;
        _lastAuthorizationStateKey = null;
        _record(
          'developer_authorization_denied',
          source: source,
          meta: const <String, Object?>{
            'mode': 'release',
            'reason': 'google_identity_session_mismatch',
          },
        );
        return false;
      }

      _record(
        'developer_authorization_allowed',
        source: source,
        meta: const <String, Object?>{
          'mode': 'release',
          'interactiveGoogle': true,
          'identityBound': true,
          'firebaseBridgeVerified': true,
        },
      );
      return true;
    } catch (error) {
      _releaseSessionAuthorized = false;
      _authorizedEmail = null;
      _lastAuthorizationStateKey = null;
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
    _lastAuthorizationStateKey = null;
    if (hadSession) {
      _record(
        'developer_authorization_cleared',
        source: source,
        meta: const <String, Object?>{'mode': 'release'},
      );
    }
  }

  static void _recordAuthorizationStateIfChanged({
    required bool authorized,
    required String mode,
    required bool releaseSessionAuthorized,
    required bool currentIdentityPresent,
    required bool authorizedEmailPresent,
    required bool emailMatches,
    required bool currentEmailAllowed,
  }) {
    final stateKey = <Object?>[
      mode,
      authorized,
      releaseSessionAuthorized,
      currentIdentityPresent,
      authorizedEmailPresent,
      emailMatches,
      currentEmailAllowed,
    ].join('|');
    if (_lastAuthorizationStateKey == stateKey) return;
    _lastAuthorizationStateKey = stateKey;
    _record(
      'developer_authorization_state_checked',
      source: 'developer_authorization_state',
      meta: <String, Object?>{
        'mode': mode,
        'authorized': authorized,
        'releaseSessionAuthorized': releaseSessionAuthorized,
        'currentIdentityPresent': currentIdentityPresent,
        'authorizedEmailPresent': authorizedEmailPresent,
        'emailMatches': emailMatches,
        'currentEmailAllowed': currentEmailAllowed,
      },
    );
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
