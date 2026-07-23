import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth show AuthClient;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/dashboard/applications/common/firebase_google_auth_bridge.dart';
import '../../features/dev/debug/debug_api_logger.dart';

class AppScopes {
  static const String calendar =
      'https://www.googleapis.com/auth/calendar';
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
        calendar,
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


class GoogleAuthIdentity {
  const GoogleAuthIdentity({
    required this.id,
    required this.email,
    required this.displayName,
  });

  final String id;
  final String email;
  final String displayName;

  String get normalizedEmail => email.trim().toLowerCase();
}

class GoogleAccountMismatchException implements Exception {
  GoogleAccountMismatchException({
    required this.expectedEmail,
    required this.actualEmail,
  });

  final String expectedEmail;
  final String actualEmail;

  @override
  String toString() => 'google_account_mismatch:$expectedEmail:$actualEmail';
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
  final StreamController<GoogleAuthIdentity?> _identityController =
      StreamController<GoogleAuthIdentity?>.broadcast();
  bool _initialized = false;

  DateTime? _lastAuthorizedAt;
  final Map<String, auth.AuthClient> _clientsByEmail =
      <String, auth.AuthClient>{};
  final Map<String, DateTime> _authorizedAtByEmail = <String, DateTime>{};
  final Map<String, GoogleAuthIdentity> _identitiesByEmail =
      <String, GoogleAuthIdentity>{};
  final Map<String, Future<auth.AuthClient>> _refreshClientFuturesByEmail =
      <String, Future<auth.AuthClient>>{};
  bool _accountSwitchInProgress = false;

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
      _clientsByEmail.clear();
      _authorizedAtByEmail.clear();
      _identitiesByEmail.clear();
      _emitIdentity();

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
      _clientsByEmail.clear();
      _authorizedAtByEmail.clear();
      _identitiesByEmail.clear();
      _emitIdentity();
      return;
    }

    try {
      final signIn = GoogleSignIn.instance;
      await signIn.initialize(serverClientId: serverClientId);

      _authSub?.cancel();
      _authSub = signIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _user = event.user;
          _client = null;
          _lastAuthorizedAt = null;
          _rememberIdentity(event.user);
          _restoreCachedClientForCurrentUser();
          _emitIdentity();
          debugPrint(
              '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signIn email=${event.user.email}');
          if (!_accountSwitchInProgress) {
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
          }
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _cacheCurrentClient();
          _user = null;
          _client = null;
          _lastAuthorizedAt = null;
          _emitIdentity();
          debugPrint(
              '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signOut');
          if (!_accountSwitchInProgress) {
            _clientsByEmail.clear();
            _authorizedAtByEmail.clear();
            _identitiesByEmail.clear();
            unawaited(
              FirebaseGoogleAuthBridge.instance
                  .signOutFirebaseOnly()
                  .catchError((Object e, StackTrace st) {
                debugPrint(
                    '[GOOGLE-AUTH][${DateTime.now().toIso8601String()}] authenticationEvents signOut -> Firebase signOut failed: $e\n$st');
              }),
            );
          }
        }
      });

      _user = await signIn.attemptLightweightAuthentication();
      if (_user != null) {
        _rememberIdentity(_user!);
        _restoreCachedClientForCurrentUser();
      }
      _emitIdentity();
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
      if (_user != null) {
        _rememberIdentity(_user!);
        _restoreCachedClientForCurrentUser();
      }

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
        _client = null;
        _lastAuthorizedAt = null;
        _rememberIdentity(user);
        _emitIdentity();
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

      invalidateClient();
      rethrow;
    }
  }

  Future<void> refreshIfNeeded() async {
    await refreshClient();
  }

  Future<auth.AuthClient> refreshClient({
    String? expectedEmail,
  }) async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('refreshClient');

    final expected = _normalizeEmail(
      expectedEmail ?? currentIdentity?.email,
    );
    final key = expected ?? '';
    final activeRefresh = _refreshClientFuturesByEmail[key];
    if (activeRefresh != null) return activeRefresh;

    final future = _performClientRefresh(expectedEmail: expected);
    _refreshClientFuturesByEmail[key] = future;

    try {
      return await future;
    } finally {
      if (identical(_refreshClientFuturesByEmail[key], future)) {
        _refreshClientFuturesByEmail.remove(key);
      }
    }
  }

  Future<auth.AuthClient> _performClientRefresh({
    String? expectedEmail,
  }) async {
    try {
      if (!_initialized) await init();
      _user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (_user != null) {
        _rememberIdentity(_user!);
        _restoreCachedClientForCurrentUser();
      }
      _emitIdentity();
      _verifyExpectedIdentity(expectedEmail);
      if (_user == null) {
        throw StateError('google_authentication_required');
      }
      _client = null;
      _lastAuthorizedAt = null;
      await _ensureAuthorizedClient(forceAuthorize: true);
      final client = _client;
      if (client == null) {
        throw StateError('google_auth_client_unavailable');
      }
      _verifyExpectedIdentity(expectedEmail);
      return client;
    } catch (e, st) {
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.refreshClient',
          'message': '토큰 강제 갱신 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'expectedEmail': expectedEmail ?? 'null',
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

  void _verifyExpectedIdentity(String? expectedEmail) {
    if (expectedEmail == null || expectedEmail.isEmpty) return;

    final identity = currentIdentity;
    if (identity == null || identity.normalizedEmail != expectedEmail) {
      throw GoogleAccountMismatchException(
        expectedEmail: expectedEmail,
        actualEmail: identity?.email ?? '',
      );
    }
  }

  Future<void> signOut() async {
    await _ensureBlockFlagLoaded();

    if (_sessionBlocked) {
      _user = null;
      _client = null;
      _lastAuthorizedAt = null;
      _clientsByEmail.clear();
      _authorizedAtByEmail.clear();
      _identitiesByEmail.clear();
      _emitIdentity();
      return;
    }

    try {
      _accountSwitchInProgress = false;
      await GoogleSignIn.instance.signOut();
      _user = null;
      _client = null;
      _lastAuthorizedAt = null;
      _clientsByEmail.clear();
      _authorizedAtByEmail.clear();
      _identitiesByEmail.clear();
      _emitIdentity();
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

  GoogleAuthIdentity? get currentIdentity {
    final user = _user;
    if (user == null) return null;
    return GoogleAuthIdentity(
      id: user.id,
      email: user.email.trim(),
      displayName: user.displayName?.trim() ?? '',
    );
  }

  Stream<GoogleAuthIdentity?> get identityChanges => _identityController.stream;

  Future<auth.AuthClient> safeClientFor({
    required String expectedEmail,
  }) async {
    final expected = _normalizeEmail(expectedEmail);
    if (expected == null) {
      throw StateError('google_account_email_required');
    }
    final cached = _cachedClientFor(expected);
    if (cached != null) return cached;
    final current = currentIdentity;
    if (current == null || current.normalizedEmail != expected) {
      throw GoogleAccountMismatchException(
        expectedEmail: expected,
        actualEmail: current?.email ?? '',
      );
    }
    final client = await safeClient();
    final after = currentIdentity;
    if (after == null || after.normalizedEmail != expected) {
      throw GoogleAccountMismatchException(
        expectedEmail: expected,
        actualEmail: after?.email ?? '',
      );
    }
    _cacheCurrentClient();
    return client;
  }

  Future<GoogleAuthIdentity> authenticateAccount({
    String? expectedEmail,
    bool forceAccountSelection = false,
    bool bridgeFirebase = true,
  }) async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('authenticateAccount');
    if (!_initialized) await init();
    final expected = _normalizeEmail(expectedEmail);
    if (!forceAccountSelection && expected != null) {
      final cachedIdentity = _identitiesByEmail[expected];
      final cachedClient = _cachedClientFor(expected);
      if (cachedIdentity != null && cachedClient != null) {
        return cachedIdentity;
      }
    }
    final current = currentIdentity;
    if (!forceAccountSelection &&
        current != null &&
        (expected == null || current.normalizedEmail == expected)) {
      await safeClientFor(expectedEmail: current.email);
      return current;
    }
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('interactive_google_auth_not_supported');
    }
    _cacheCurrentClient();
    _accountSwitchInProgress = true;
    try {
      if (_user != null) {
        await GoogleSignIn.instance.signOut();
        _user = null;
        _client = null;
        _lastAuthorizedAt = null;
        _emitIdentity();
      }
      final user = await GoogleSignIn.instance.authenticate();
      _user = user;
      _client = null;
      _lastAuthorizedAt = null;
      _rememberIdentity(user);
      _emitIdentity();
      if (bridgeFirebase) {
        await FirebaseGoogleAuthBridge.instance.ensureSignedInWithGoogleUser(user);
      }
      final identity = currentIdentity!;
      if (expected != null && identity.normalizedEmail != expected) {
        throw GoogleAccountMismatchException(
          expectedEmail: expected,
          actualEmail: identity.email,
        );
      }
      await _ensureAuthorizedClient(forceAuthorize: true);
      if (_client == null) {
        throw StateError('google_auth_client_unavailable');
      }
      _cacheCurrentClient();
      return identity;
    } finally {
      _accountSwitchInProgress = false;
    }
  }

  bool hasCachedClientFor(String email) {
    final normalized = _normalizeEmail(email);
    if (normalized == null) return false;
    return _cachedClientFor(normalized) != null;
  }

  GoogleAuthIdentity? cachedIdentityFor(String email) {
    final normalized = _normalizeEmail(email);
    return normalized == null ? null : _identitiesByEmail[normalized];
  }

  void forgetAccount(String email) {
    final normalized = _normalizeEmail(email);
    if (normalized == null) return;
    _clientsByEmail.remove(normalized);
    _authorizedAtByEmail.remove(normalized);
    _identitiesByEmail.remove(normalized);
    if (currentIdentity?.normalizedEmail == normalized) {
      _client = null;
      _lastAuthorizedAt = null;
    }
  }

  void invalidateClient({String? accountEmail}) {
    final normalized = _normalizeEmail(accountEmail ?? currentIdentity?.email);
    if (normalized != null) {
      _clientsByEmail.remove(normalized);
      _authorizedAtByEmail.remove(normalized);
    }
    if (normalized == null || currentIdentity?.normalizedEmail == normalized) {
      _client = null;
      _lastAuthorizedAt = null;
    }
  }

  void _emitIdentity() {
    if (_identityController.isClosed) return;
    _identityController.add(currentIdentity);
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
      _cacheCurrentClient();
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

  String? _normalizeEmail(String? email) {
    final normalized = email?.trim().toLowerCase();
    return normalized?.isNotEmpty == true ? normalized : null;
  }

  void _rememberIdentity(GoogleSignInAccount user) {
    final identity = GoogleAuthIdentity(
      id: user.id,
      email: user.email.trim(),
      displayName: user.displayName?.trim() ?? '',
    );
    _identitiesByEmail[identity.normalizedEmail] = identity;
  }

  void _cacheCurrentClient() {
    final identity = currentIdentity;
    final client = _client;
    final authorizedAt = _lastAuthorizedAt;
    if (identity == null || client == null || authorizedAt == null) return;
    _clientsByEmail[identity.normalizedEmail] = client;
    _authorizedAtByEmail[identity.normalizedEmail] = authorizedAt;
    _identitiesByEmail[identity.normalizedEmail] = identity;
  }

  void _restoreCachedClientForCurrentUser() {
    final identity = currentIdentity;
    if (identity == null) return;
    final client = _cachedClientFor(identity.normalizedEmail);
    if (client == null) return;
    _client = client;
    _lastAuthorizedAt = _authorizedAtByEmail[identity.normalizedEmail];
  }

  auth.AuthClient? _cachedClientFor(String normalizedEmail) {
    final client = _clientsByEmail[normalizedEmail];
    final authorizedAt = _authorizedAtByEmail[normalizedEmail];
    if (client == null || authorizedAt == null) return null;
    if (DateTime.now().difference(authorizedAt) > _maxClientAge &&
        currentIdentity?.normalizedEmail == normalizedEmail) {
      _clientsByEmail.remove(normalizedEmail);
      _authorizedAtByEmail.remove(normalizedEmail);
      _client = null;
      _lastAuthorizedAt = null;
      return null;
    }
    return client;
  }

  void dispose() {
    _authSub?.cancel();
    _authSub = null;
  }

  static bool isInvalidTokenError(Object e) {
    final dynamic error = e;

    try {
      final status = error.status;
      if (status == 401 || status?.toString() == '401') return true;
    } catch (_) {}

    try {
      final code = error.code;
      if (code == 401 || code?.toString() == '401') return true;
    } catch (_) {}

    try {
      final errors = error.errors;
      if (errors is Iterable) {
        for (final item in errors) {
          if (_containsAuthenticationFailure(item.toString())) return true;
        }
      }
    } catch (_) {}

    return _containsAuthenticationFailure(e.toString());
  }

  static bool _containsAuthenticationFailure(String value) {
    final message = value.toLowerCase();
    return message.contains('invalid_token') ||
        message.contains('invalid credentials') ||
        message.contains('invalid authentication credentials') ||
        message.contains('request had invalid authentication credentials') ||
        message.contains('login required') ||
        message.contains('autherror') ||
        message.contains('unauthenticated') ||
        message.contains('access token expired') ||
        message.contains('token has expired') ||
        message.contains('token expired') ||
        message.contains('access was denied') ||
        message.contains('status: 401') ||
        message.contains('statuscode: 401') ||
        message.contains('status code: 401') ||
        message.contains('code: 401') ||
        message.contains('http 401');
  }
}
