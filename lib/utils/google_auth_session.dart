// File: lib/xxx/google_auth_session.dart  (예시 경로)
//
// ⚠️ 아래 import 경로는 현재 프로젝트 구조에 맞게 수정하세요.
import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth show AuthClient;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../screens/dev_package/debug_package/debug_api_logger.dart';

// DebugApiLogger 경로는 실제 파일 위치에 맞게 조정

class AppScopes {
  static const String calendarEvents = 'https://www.googleapis.com/auth/calendar.events';
  static const String spreadsheets = 'https://www.googleapis.com/auth/spreadsheets';
  static const String documents = 'https://www.googleapis.com/auth/documents';
  static const String gmailSend = 'https://www.googleapis.com/auth/gmail.send';
  static const String driveFile = 'https://www.googleapis.com/auth/drive.file';
  static const String gcsFullControl = 'https://www.googleapis.com/auth/devstorage.full_control';

  static List<String> all() => <String>{
        calendarEvents,
        spreadsheets,
        documents,
        gmailSend,
        driveFile,
        gcsFullControl,
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

  Future<void> init({
    String? serverClientId,
    List<String>? additionalScopes,
  }) async {
    // 이미 초기화된 경우: 스코프만 merge
    if (_initialized) {
      final merged = {..._scopes, ...?additionalScopes};
      _scopes = merged.toList();
      return;
    }

    // _scopes를 먼저 만들어 놓고, 그 이후 과정을 try/catch
    _scopes = {...AppScopes.all(), ...?additionalScopes}.toList();
    _initialized = true;

    try {
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

      // 앱 실행 시 자동 로그인을 시도 (실패해도 예외는 안 던짐)
      _user = await signIn.attemptLightweightAuthentication();
      _client = null;
    } catch (e, st) {
      // 🔴 초기화/경량 인증에서 실패한 경우
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.init',
          'message': 'GoogleSignIn 초기화 또는 lightweight 인증 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'serverClientId': serverClientId ?? 'null',
          'scopes': _scopes,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  Future<auth.AuthClient> client() async {
    try {
      // 아직 init 안 되어 있으면 기본 스코프로 init
      if (!_initialized) {
        await init();
      }

      // 사용자 없으면 경량 인증 한 번 더 시도
      _user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();

      // 기존 클라이언트가 있으면 그대로 사용
      if (_client != null) return _client!;

      // 이미 로그인된 유저가 있으면 스코프 확인/부여
      if (_user != null) {
        await _ensureAuthorizedClient();
        if (_client != null) return _client!;
      }

      // authenticate() 지원하는 플랫폼이면 풀 로그인 시도
      if (GoogleSignIn.instance.supportsAuthenticate()) {
        final user = await GoogleSignIn.instance.authenticate();
        _user = user;
        await _ensureAuthorizedClient();
        if (_client != null) return _client!;
      }

      // 여기까지 왔으면 더 이상 시도할 방법이 없음
      throw StateError('AuthClient 생성 실패: 로그인/스코프 권한 확인 필요');
    } catch (e, st) {
      // 🔴 AuthClient 생성 실패 원인 로깅
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.client',
          'message': 'AuthClient 생성 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  Future<void> refreshIfNeeded() async {
    // 기존 클라이언트 버리고, 강제로 재인증/재발급
    _client = null;
    try {
      await _ensureAuthorizedClient(forceAuthorize: true);
    } catch (e, st) {
      // 🔴 토큰 재발급/스코프 재부여 실패
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.refreshIfNeeded',
          'message': '토큰 강제 갱신 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
      _user = null;
      _client = null;
    } catch (e, st) {
      // signOut은 필수는 아니지만, 실패하면 참고용으로 남겨두면 좋음
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.signOut',
          'message': 'Google SignOut 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
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
    if (_user == null) return;

    try {
      // 이미 권한이 있는지 우선 확인
      var authorization = forceAuthorize ? null : await _user!.authorizationClient.authorizationForScopes(_scopes);

      // 없으면 새로 authorize
      authorization ??= await _user!.authorizationClient.authorizeScopes(_scopes);

      _client = authorization.authClient(scopes: _scopes);
    } catch (e, st) {
      // 🔴 스코프 권한 부여/토큰 발급 실패
      await DebugApiLogger().log(
        {
          'tag': 'GoogleAuthSession.ensureAuthorizedClient',
          'message': '스코프 권한 부여 또는 토큰 발급 실패',
          'error': e.toString(),
          'stack': st.toString(),
          'userEmail': _user?.email ?? 'null',
          'scopes': _scopes,
          'forceAuthorize': forceAuthorize,
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
}
