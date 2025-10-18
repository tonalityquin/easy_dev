// lib/utils/google_auth_session.dart
//
// Google 계정 인증을 앱 전역에서 "한 번"만 수행하고,
// 이후 Calendar / Sheets / Docs / GCS 등 모든 기능이 동일한 AuthClient를 재사용하는 세션.
// google_sign_in v7 API에 맞춰 작성.

import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth show AuthClient;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class AppScopes {
  static const String calendarEvents = 'https://www.googleapis.com/auth/calendar.events';
  static const String spreadsheets   = 'https://www.googleapis.com/auth/spreadsheets';
  static const String documents      = 'https://www.googleapis.com/auth/documents';
  // GCS 업로드까지 사용한다면 full_control 사용(환경에 따라 read_write로 낮춰도 됨)
  static const String gcsFullControl = 'https://www.googleapis.com/auth/devstorage.full_control';
  // static const String gcsReadWrite = 'https://www.googleapis.com/auth/devstorage.read_write';

  static List<String> all() => <String>{
    calendarEvents,
    spreadsheets,
    documents,
    gcsFullControl, // 또는 gcsReadWrite
  }.toList();
}

class GoogleAuthSession {
  GoogleAuthSession._();
  static final GoogleAuthSession instance = GoogleAuthSession._();

  GoogleSignInAccount? _user;
  auth.AuthClient? _client;
  late List<String> _scopes;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;
  bool _initialized = false;

  /// 앱 시작 시 한 번 호출 (팝업 없이 조용한 복구만 수행)
  Future<void> init({
    String? serverClientId,
    List<String>? additionalScopes,
  }) async {
    if (_initialized) return;
    _initialized = true;

    _scopes = {...AppScopes.all(), ...?additionalScopes}.toList();

    final signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: serverClientId);

    _authSub?.cancel();
    _authSub = signIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _user = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _user = null;
        _client = null;
      }
    });

    // ❌ 여기서 authenticate()를 호출하지 않음 — 조용한 복구만
    _user = await signIn.attemptLightweightAuthentication();

    // 실제 API 사용 시 client()에서 한 번만 승인/생성
    _client = null;
  }

  /// 실제 API 사용 시 호출 — 최초 1회만 스코프 승인 프롬프트가 있을 수 있음
  Future<auth.AuthClient> client() async {
    if (!_initialized) {
      await init();
    }

    // 앱 재시작 등으로 _user가 비었으면 조용히 복구 시도
    if (_user == null) {
      _user = await GoogleSignIn.instance.attemptLightweightAuthentication();
    }

    if (_client != null) return _client!;

    if (_user != null) {
      await _ensureAuthorizedClient();
      if (_client != null) return _client!;
    }

    // 최초 실행 등으로 세션이 전혀 없을 때만, 실제 사용 타이밍에 1회 authenticate 허용
    if (GoogleSignIn.instance.supportsAuthenticate()) {
      final user = await GoogleSignIn.instance.authenticate();
      _user = user;
      await _ensureAuthorizedClient();
      if (_client != null) return _client!;
    }

    throw StateError('AuthClient 생성 실패: 로그인/스코프 권한 확인 필요');
  }

  Future<void> refreshIfNeeded() async {
    _client = null;
    await _ensureAuthorizedClient(forceAuthorize: true);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _user = null;
    _client = null;
  }

  GoogleSignInAccount? get currentUser => _user;
  List<String> get grantedScopes => List.unmodifiable(_scopes);

  Future<void> _ensureAuthorizedClient({bool forceAuthorize = false}) async {
    if (_user == null) return;

    var authorization = forceAuthorize
        ? null
        : await _user!.authorizationClient.authorizationForScopes(_scopes);

    // 이미 승인됐다면 조용히 통과, 아니라면 "이번 한 번"만 프롬프트
    authorization ??= await _user!.authorizationClient.authorizeScopes(_scopes);

    _client = authorization.authClient(scopes: _scopes);
  }

  void dispose() {
    _authSub?.cancel();
    _authSub = null;
  }
}
