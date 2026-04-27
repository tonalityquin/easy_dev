import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth show AuthClient;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dev/debug/debug_api_logger.dart';
import '../../services/firebase_google_auth_bridge.dart';

class AppScopes {
  static const String calendarEvents =
      'https://www.googleapis.com/auth/calendar.events';
  static const String spreadsheets =
      'https://www.googleapis.com/auth/spreadsheets';
  static const String documents = 'https://www.googleapis.com/auth/documents';
  static const String gmailSend = 'https://www.googleapis.com/auth/gmail.send';
  static const String driveFile = 'https://www.googleapis.com/auth/drive.file';
  static const String gcsFullControl =
      'https://www.googleapis.com/auth/devstorage.full_control';

  static List<String> all() => <String>{
        calendarEvents,
        spreadsheets,
        documents,
        gmailSend,
        driveFile,
        gcsFullControl,
      }.toList();
}

class GoogleSessionBlockedException implements Exception {
  final String message;

  GoogleSessionBlockedException([this.message = '구글 세션 시도 차단(ON) 상태입니다.']);

  @override
  String toString() => message;
}

class GoogleAuthSession {
  GoogleAuthSession._();

  static final GoogleAuthSession instance = GoogleAuthSession._();

  static const String prefsKeyBlockGoogleSession =
      'debug_block_google_session_attempts_v1';

  GoogleSignInAccount? _user;
  auth.AuthClient? _client;
  late List<String> _scopes;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;
  bool _initialized = false;

  DateTime? _lastAuthorizedAt;

  Duration _maxClientAge = const Duration(minutes: 30);

  bool _sessionBlocked = false;
  bool _blockFlagLoaded = false;
  Completer<void>? _blockLoadCompleter;

  bool get isSessionBlocked => _sessionBlocked;

  void setMaxClientAge(Duration duration) {
    _maxClientAge = duration;
  }

  Future<void> _ensureBlockFlagLoaded() async {
    if (_blockFlagLoaded) return;

    if (_blockLoadCompleter != null) {
      return _blockLoadCompleter!.future;
    }

    _blockLoadCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionBlocked = prefs.getBool(prefsKeyBlockGoogleSession) ?? false;
      _blockFlagLoaded = true;
      _blockLoadCompleter!.complete();
    } catch (e, st) {
      _blockLoadCompleter!.completeError(e, st);
      rethrow;
    } finally {
      _blockLoadCompleter = null;
    }
  }

  Future<void> warmUpBlockFlag() async {
    try {
      await _ensureBlockFlagLoaded();
    } catch (_) {}
  }

  Future<void> setSessionBlocked(bool blocked) async {
    await _ensureBlockFlagLoaded();

    _sessionBlocked = blocked;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKeyBlockGoogleSession, blocked);

    if (blocked) {
      _client = null;
      _user = null;
      _lastAuthorizedAt = null;

      await _authSub?.cancel();
      _authSub = null;
    }
  }

  void _throwIfBlocked(String op) {
    if (!_sessionBlocked) return;
    throw GoogleSessionBlockedException('구글 세션 시도 차단(ON): $op');
  }

  Future<void> init({
    String? serverClientId,
    List<String>? additionalScopes,
  }) async {
    await _ensureBlockFlagLoaded();

    if (_initialized) {
      final merged = {..._scopes, ...?additionalScopes};
      _scopes = merged.toList();
      return;
    }

    _scopes = {...AppScopes.all(), ...?additionalScopes}.toList();
    _initialized = true;

    if (_sessionBlocked) {
      _client = null;
      _user = null;
      _lastAuthorizedAt = null;
      return;
    }

    try {
      final signIn = GoogleSignIn.instance;
      await signIn.initialize(serverClientId: serverClientId);

      _authSub?.cancel();
      _authSub = signIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _user = event.user;
          debugPrint(
              '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signIn email=${event.user.email}');
          unawaited(
            FirebaseGoogleAuthBridge.instance
                .ensureSignedInWithGoogleUser(event.user)
                .then((ok) {
              debugPrint(
                  '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signIn -> Firebase bridge ok=$ok email=${event.user.email}');
            }).catchError((Object e, StackTrace st) {
              debugPrint(
                  '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signIn -> Firebase bridge failed: $e\n$st');
            }),
          );
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _user = null;
          _client = null;
          _lastAuthorizedAt = null;
          debugPrint(
              '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signOut');
          unawaited(
            FirebaseGoogleAuthBridge.instance
                .signOutFirebaseOnly()
                .catchError((Object e, StackTrace st) {
              debugPrint(
                  '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signOut -> Firebase signOut failed: $e\n$st');
            }),
          );
        }
      });

      _user = await signIn.attemptLightweightAuthentication();
      debugPrint(
          '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] init lightweight result email=${_user?.email}');
      if (_user != null) {
        unawaited(
          FirebaseGoogleAuthBridge.instance
              .ensureSignedInWithGoogleUser(_user!)
              .then((ok) {
            debugPrint(
                '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] init lightweight -> Firebase bridge ok=$ok email=${_user?.email}');
          }).catchError((Object e, StackTrace st) {
            debugPrint(
                '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] init lightweight -> Firebase bridge failed: $e\n$st');
          }),
        );
      }
      _client = null;
      _lastAuthorizedAt = null;
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.init',
          'message': 'GoogleSignIn 초기화 또는 lightweight 인증 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'serverClientId': serverClientId ?? 'null',
          'scopes': _scopes,
          'sessionBlocked': _sessionBlocked,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  Future<auth.AuthClient> _rawClient() async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('_rawClient');

    try {
      if (!_initialized) {
        await init();
      }

      _user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();

      if (_client != null && _lastAuthorizedAt != null) {
        final age = DateTime.now().difference(_lastAuthorizedAt!);
        if (age > _maxClientAge) {
          _client = null;
        }
      }

      if (_client != null) return _client!;

      if (_user != null) {
        await _ensureAuthorizedClient();
        if (_client != null) return _client!;
      }

      if (GoogleSignIn.instance.supportsAuthenticate()) {
        final user = await GoogleSignIn.instance.authenticate();
        _user = user;
        debugPrint(
            '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] interactive authenticate success email=${user.email}');
        final firebaseOk = await FirebaseGoogleAuthBridge.instance
            .ensureSignedInWithGoogleUser(user);
        debugPrint(
            '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] interactive authenticate -> Firebase bridge ok=$firebaseOk email=${user.email}');
        await _ensureAuthorizedClient();
        if (_client != null) return _client!;
      }

      throw StateError('AuthClient 생성 실패: 로그인/스코프 권한 확인 필요');
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession._rawClient',
          'message': 'AuthClient 생성 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
          'sessionBlocked': _sessionBlocked,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  Future<auth.AuthClient> safeClient() async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('safeClient');

    try {
      return await _rawClient();
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.safeClient',
          'message': 'safeClient에서 AuthClient 획득 실패 -> signOut 시도',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
          'sessionBlocked': _sessionBlocked,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );

      try {
        await signOut();
      } catch (_) {}

      rethrow;
    }
  }

  Future<void> refreshIfNeeded() async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('refreshIfNeeded');

    _client = null;
    _lastAuthorizedAt = null;

    try {
      await _ensureAuthorizedClient(forceAuthorize: true);
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.refreshIfNeeded',
          'message': '토큰 강제 갱신 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
          'sessionBlocked': _sessionBlocked,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _ensureBlockFlagLoaded();

    if (_sessionBlocked) {
      _user = null;
      _client = null;
      _lastAuthorizedAt = null;
      return;
    }

    try {
      await GoogleSignIn.instance.signOut();
      _user = null;
      _client = null;
      _lastAuthorizedAt = null;
      await FirebaseGoogleAuthBridge.instance.signOutFirebaseOnly();
      debugPrint(
          '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] GoogleAuthSession.signOut -> Firebase signOut complete');
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.signOut',
          'message': 'Google SignOut 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'sessionBlocked': _sessionBlocked,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  GoogleSignInAccount? get currentUser => _user;

  List<String> get grantedScopes => List.unmodifiable(_scopes);

  Future<void> _ensureAuthorizedClient({bool forceAuthorize = false}) async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('_ensureAuthorizedClient');

    if (_user == null) return;

    try {
      var authorization = forceAuthorize
          ? null
          : await _user!.authorizationClient.authorizationForScopes(_scopes);

      authorization ??=
          await _user!.authorizationClient.authorizeScopes(_scopes);

      _client = authorization.authClient(scopes: _scopes);
      _lastAuthorizedAt = DateTime.now();
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.ensureAuthorizedClient',
          'message': '스코프 권한 부여 또는 토큰 발급 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
          'forceAuthorize': forceAuthorize,
          'sessionBlocked': _sessionBlocked,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  void dispose() {
    _authSub?.cancel();
    _authSub = null;
  }

  static bool isInvalidTokenError(Object e) {
    final msg = e.toString();

    if (msg.contains('invalid_token')) return true;
    if (msg.contains('Access was denied')) return true;

    return false;
  }
}
