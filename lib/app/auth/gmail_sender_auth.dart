import 'package:http/http.dart' as http;

import '../config/gmail_sender_config.dart';
import 'gmail_sender_diagnostics.dart';
import 'google_auth_session.dart';

class GmailSenderStatus {
  const GmailSenderStatus({
    required this.configuredEmail,
    required this.authenticatedEmail,
  });

  final String configuredEmail;
  final String authenticatedEmail;

  bool get configured => configuredEmail.isNotEmpty;
  bool get authenticated => authenticatedEmail.isNotEmpty;
  bool get matches => configured &&
      authenticated &&
      configuredEmail.toLowerCase() == authenticatedEmail.toLowerCase();

  String get state {
    if (!configured) return 'NOT_CONFIGURED';
    if (!authenticated) return 'AUTH_REQUIRED';
    return matches ? 'MATCH' : 'MISMATCH';
  }

  List<String> get statusLines => <String>[
        'configured      ${configured ? configuredEmail : '-'}',
        'authenticated   ${authenticated ? authenticatedEmail : '-'}',
        'status          $state',
        'domain          ${GmailSenderConfig.suffix}',
      ];

  String get developerDescription => <String>[
        'Gmail configured: ${configured ? configuredEmail : '-'}',
        'Gmail authenticated: ${authenticated ? authenticatedEmail : '-'}',
        'Gmail account match: $matches',
        'Gmail sender state: $state',
        'Gmail domain: ${GmailSenderConfig.suffix}',
      ].join('\n');
}

class GmailSenderAuth {
  GmailSenderAuth._();

  static Future<GmailSenderStatus> status({bool initializeDefault = true}) async {
    final current = GoogleAuthSession.instance.currentIdentity?.email.trim() ?? '';
    if (initializeDefault) {
      final initialized =
          await GmailSenderConfig.initializeFromEmailIfUnset(current);
      if (initialized) {
        GmailSenderDiagnostics.record(
          'config_initialized_from_oauth',
          meta: <String, Object?>{'email': current},
        );
      }
    }
    final configured = await GmailSenderConfig.readEmail() ?? '';
    final snapshot = GmailSenderStatus(
      configuredEmail: configured,
      authenticatedEmail: current,
    );
    GmailSenderDiagnostics.record(
      'status',
      meta: <String, Object?>{
        'configured': configured.isEmpty ? '-' : configured,
        'authenticated': current.isEmpty ? '-' : current,
        'state': snapshot.state,
      },
    );
    return snapshot;
  }

  static Future<http.Client> client() async {
    final snapshot = await status();
    if (!snapshot.configured) {
      GmailSenderDiagnostics.record('client_blocked', meta: const <String, Object?>{
        'reason': 'not_configured',
      });
      throw StateError('Gmail 발신 계정이 설정되지 않았습니다. Terminal ~/setting에서 edit email을 실행해 주세요.');
    }
    if (!snapshot.authenticated || !snapshot.matches) {
      GmailSenderDiagnostics.record(
        'client_blocked',
        meta: <String, Object?>{
          'reason': snapshot.authenticated ? 'account_mismatch' : 'auth_required',
          'expected': snapshot.configuredEmail,
          'actual': snapshot.authenticatedEmail.isEmpty ? '-' : snapshot.authenticatedEmail,
        },
      );
      throw GoogleAccountMismatchException(
        expectedEmail: snapshot.configuredEmail,
        actualEmail: snapshot.authenticatedEmail,
      );
    }
    await GoogleAuthSession.instance.refreshClient(
      expectedEmail: snapshot.configuredEmail,
    );
    final client = await GoogleAuthSession.instance.safeClientFor(
      expectedEmail: snapshot.configuredEmail,
    );
    GmailSenderDiagnostics.record(
      'client_ready',
      meta: <String, Object?>{'expected': snapshot.configuredEmail},
    );
    return client;
  }

  static Future<GmailSenderStatus> authenticateAndSetLocalPart(
    String rawLocalPart,
  ) async {
    final localPart = GmailSenderConfig.normalizeLocalPart(rawLocalPart);
    if (!GmailSenderConfig.isValidLocalPart(localPart)) {
      GmailSenderDiagnostics.record(
        'edit_rejected',
        meta: <String, Object?>{'reason': 'invalid_local_part'},
      );
      throw const FormatException('gmail_sender_local_part_invalid');
    }
    final expectedEmail = GmailSenderConfig.emailForLocalPart(localPart);
    final before = await GmailSenderConfig.readEmail() ?? '';
    final current = GoogleAuthSession.instance.currentIdentity;
    GmailSenderDiagnostics.record(
      'edit_auth_start',
      meta: <String, Object?>{
        'before': before.isEmpty ? '-' : before,
        'expected': expectedEmail,
        'current': current?.email ?? '-',
      },
    );
    if (current == null || current.normalizedEmail != expectedEmail) {
      await GoogleAuthSession.instance.authenticateAccount(
        expectedEmail: expectedEmail,
        forceAccountSelection: true,
        bridgeFirebase: false,
      );
    } else {
      await GoogleAuthSession.instance.safeClientFor(
        expectedEmail: expectedEmail,
      );
    }
    final authenticated = GoogleAuthSession.instance.currentIdentity;
    if (authenticated == null || authenticated.normalizedEmail != expectedEmail) {
      GmailSenderDiagnostics.record(
        'edit_auth_mismatch',
        meta: <String, Object?>{
          'expected': expectedEmail,
          'actual': authenticated?.email ?? '-',
        },
      );
      throw GoogleAccountMismatchException(
        expectedEmail: expectedEmail,
        actualEmail: authenticated?.email ?? '',
      );
    }
    await GmailSenderConfig.setLocalPart(localPart);
    final snapshot = await status(initializeDefault: false);
    GmailSenderDiagnostics.record(
      'edit_saved',
      meta: <String, Object?>{
        'before': before.isEmpty ? '-' : before,
        'next': expectedEmail,
        'state': snapshot.state,
      },
    );
    return snapshot;
  }
}
