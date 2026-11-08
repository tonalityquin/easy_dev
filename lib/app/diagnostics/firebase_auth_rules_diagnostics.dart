import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';
import '../utils/secure_auth_diagnostics.dart';

@immutable
class FirebaseAuthRulesSnapshot {
  const FirebaseAuthRulesSnapshot({
    required this.checkedAt,
    required this.sessionUid,
    required this.provider,
    required this.emailVerified,
    required this.developerEmailMatch,
    required this.status,
    required this.sessionGeneration,
  });

  final DateTime checkedAt;
  final String? sessionUid;
  final String provider;
  final bool? emailVerified;
  final bool? developerEmailMatch;
  final String status;
  final int sessionGeneration;

  bool get signedInEligible =>
      sessionUid != null && provider == 'google.com' && emailVerified == true;

  bool get developerEligible => signedInEligible && developerEmailMatch == true;

  bool get complete => status == 'checked' || status == 'signed_out';

  String get summary {
    if (status == 'error') return '인증 상태: 검사 실패';
    if (status == 'not_checked') return '인증 상태: 확인되지 않음';
    if (sessionUid == null) return '인증 상태: Firebase 로그인 없음';
    return 'Google Rules 조건: ${signedInEligible ? '충족' : '미충족'} · '
        '개발자 조건: ${developerEligible ? '충족' : '미충족'}';
  }
}

@immutable
class FirebaseAuthSessionIdentity {
  const FirebaseAuthSessionIdentity({
    required this.uid,
    required this.generation,
    required this.available,
  });

  final String? uid;
  final int generation;
  final bool available;
}

class FirebaseAuthRulesDiagnostics {
  FirebaseAuthRulesDiagnostics._();

  static const String developerEmail = 'surge1868@gmail.com';
  static final List<String> _lines = <String>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _authTrackingStarted = false;
  static bool _authTrackingAvailable = false;
  static bool _initialAuthEventPending = true;
  static String? _observedUid;
  static int _sessionGeneration = 0;

  static void _ensureAuthTracking() {
    if (_authTrackingStarted) return;
    _authTrackingStarted = true;
    try {
      final auth = FirebaseAuth.instance;
      _observedUid = auth.currentUser?.uid;
      _authTrackingAvailable = true;
      auth.authStateChanges().listen(
        (user) {
          final nextUid = user?.uid;
          if (_initialAuthEventPending) {
            _initialAuthEventPending = false;
            if (nextUid != _observedUid) _sessionGeneration++;
          } else {
            _sessionGeneration++;
          }
          _observedUid = nextUid;
        },
        onError: (Object _) {
          _authTrackingAvailable = false;
        },
      );
    } catch (_) {
      _authTrackingAvailable = false;
    }
  }

  static FirebaseAuthSessionIdentity captureSessionIdentity() {
    _ensureAuthTracking();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (_authTrackingAvailable && uid != _observedUid) {
        _sessionGeneration++;
        _observedUid = uid;
      }
      return FirebaseAuthSessionIdentity(
        uid: uid,
        generation: _sessionGeneration,
        available: _authTrackingAvailable,
      );
    } catch (_) {
      return FirebaseAuthSessionIdentity(
        uid: null,
        generation: _sessionGeneration,
        available: false,
      );
    }
  }

  static String sessionEvidence(
    FirebaseAuthSessionIdentity started,
    FirebaseAuthSessionIdentity current,
  ) {
    if (!started.available || !current.available) return 'AUTH_UNAVAILABLE';
    if (started.uid == null) return 'AUTH_AT_START_UNAVAILABLE';
    if (current.uid == null) return 'AUTH_SIGNED_OUT';
    if (started.uid != current.uid) return 'AUTH_CHANGED';
    if (started.generation != current.generation) {
      return 'AUTH_SESSION_CHANGED';
    }
    return 'MATCH';
  }

  static bool isSameSessionIdentity(FirebaseAuthSessionIdentity identity) {
    final currentIdentity = captureSessionIdentity();
    return identity.available && currentIdentity.available &&
        identity.uid == currentIdentity.uid &&
        identity.generation == currentIdentity.generation;
  }

  static FirebaseAuthRulesSnapshot _latest = FirebaseAuthRulesSnapshot(
    checkedAt: DateTime.fromMillisecondsSinceEpoch(0),
    sessionUid: null,
    provider: 'unknown',
    emailVerified: null,
    developerEmailMatch: null,
    status: 'not_checked',
    sessionGeneration: 0,
  );

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static FirebaseAuthRulesSnapshot? get current {
    final value = _latest;
    if (!value.complete) return null;
    final identity = captureSessionIdentity();
    if (!identity.available || identity.uid != value.sessionUid ||
        identity.generation != value.sessionGeneration) return null;
    if (DateTime.now().difference(value.checkedAt) >
        const Duration(minutes: 10)) return null;
    return value;
  }

  static FirebaseAuthRulesSnapshot? captureForRequest() {
    if (!DevAuth.devModeEnabled.value) return null;
    try {
      return current;
    } catch (_) {
      return null;
    }
  }

  static bool isSameSession(FirebaseAuthRulesSnapshot? snapshot) {
    if (snapshot == null) return false;
    final identity = captureSessionIdentity();
    return identity.available && identity.uid == snapshot.sessionUid &&
        identity.generation == snapshot.sessionGeneration;
  }

  static void _record(FirebaseAuthRulesSnapshot snapshot, String source) {
    if (!DevAuth.devModeEnabled.value) return;
    final line = <String>[
      '[FIREBASE_AUTH_AUDIT]',
      'timestamp=${snapshot.checkedAt.toIso8601String()}',
      'source=${source.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '_')}',
      'firebaseUser=${snapshot.sessionUid != null}',
      'signInProvider=${snapshot.provider}',
      'emailVerified=${snapshot.emailVerified ?? 'unknown'}',
      'developerEmailMatch=${snapshot.developerEmailMatch ?? 'unknown'}',
      'signInEligible=${snapshot.signedInEligible}',
      'developerEligible=${snapshot.developerEligible}',
      'status=${snapshot.status}',
      'evidence=CLIENT_TOKEN',
    ].join(' ');
    final safe = SecureAuthDiagnostics.redact(line);
    debugPrint(safe);
    _lines.add(safe);
    revision.value++;
    if (_lines.length > 240) _lines.removeRange(0, _lines.length - 240);
  }

  static Future<FirebaseAuthRulesSnapshot> inspect({
    required String source,
  }) async {
    final now = DateTime.now();
    final identityAtStart = captureSessionIdentity();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final result = FirebaseAuthRulesSnapshot(
        checkedAt: now,
        sessionUid: null,
        provider: 'none',
        emailVerified: false,
        developerEmailMatch: false,
        status: 'signed_out',
        sessionGeneration: identityAtStart.generation,
      );
      _latest = result;
      _record(result, source);
      return result;
    }
    try {
      final token = await user.getIdTokenResult();
      final claims = token.claims;
      final provider = token.signInProvider ?? 'unknown';
      final verified = claims?['email_verified'];
      final tokenEmail = claims?['email'];
      final result = FirebaseAuthRulesSnapshot(
        checkedAt: DateTime.now(),
        sessionUid: user.uid,
        provider: provider,
        emailVerified: verified is bool ? verified : null,
        developerEmailMatch: tokenEmail is String
            ? tokenEmail == developerEmail
            : null,
        status: 'checked',
        sessionGeneration: identityAtStart.generation,
      );
      if (!isSameSessionIdentity(identityAtStart)) {
        return await inspect(source: '${source}_session_changed');
      }
      _latest = result;
      _record(result, source);
      return result;
    } catch (error) {
      final result = FirebaseAuthRulesSnapshot(
        checkedAt: DateTime.now(),
        sessionUid: user.uid,
        provider: 'unknown',
        emailVerified: null,
        developerEmailMatch: null,
        status: 'error',
        sessionGeneration: identityAtStart.generation,
      );
      _latest = result;
      _record(result, source);
      if (DevAuth.devModeEnabled.value) {
        final code = error is FirebaseAuthException
            ? error.code
            : error.runtimeType.toString();
        final safe = SecureAuthDiagnostics.redact(
          '[FIREBASE_AUTH_AUDIT] source=$source result=error errorType=$code',
        );
        debugPrint(safe);
        _lines.add(safe);
        if (_lines.length > 240) _lines.removeRange(0, _lines.length - 240);
      }
      return result;
    }
  }

  static String get debugPrintCode => lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');
}
