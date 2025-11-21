// File: lib/utils/google_auth_session.dart  (예시 경로)
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

  /// 마지막으로 authorize(토큰/스코프 부여)에 성공한 시각
  DateTime? _lastAuthorizedAt;

  /// _client 최대 허용 수명 (TTL)
  Duration _maxClientAge = const Duration(minutes: 30);

  /// 외부에서 TTL을 조절하고 싶을 때 사용
  void setMaxClientAge(Duration duration) {
    _maxClientAge = duration;
  }

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
          _lastAuthorizedAt = null;
        }
      });

      // 앱 실행 시 자동 로그인을 시도 (실패해도 예외는 안 던짐)
      _user = await signIn.attemptLightweightAuthentication();
      _client = null;
      _lastAuthorizedAt = null;
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

  /// 내부용 AuthClient 획득 함수
  ///
  /// - TTL 이내라면 기존 _client 재사용
  /// - TTL이 지났거나 _client가 없으면 다시 authorize
  Future<auth.AuthClient> _rawClient() async {
    try {
      // 아직 init 안 되어 있으면 기본 스코프로 init
      if (!_initialized) {
        await init();
      }

      // 사용자 없으면 경량 인증 한 번 더 시도
      _user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();

      // 🔹 TTL 체크: 너무 오래된 클라이언트는 버림
      if (_client != null && _lastAuthorizedAt != null) {
        final age = DateTime.now().difference(_lastAuthorizedAt!);
        if (age > _maxClientAge) {
          _client = null;
        }
      }

      // TTL 안쪽이고, 기존 클라이언트가 있으면 그대로 사용
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
          'tag': 'GoogleAuthSession._rawClient',
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

  /// 비즈니스 로직에서 사용하는 AuthClient 획득 함수 (외부에서는 이거만 쓰면 됨)
  ///
  /// - 내부적으로 _rawClient()를 호출
  /// - 실패 시 signOut까지 시도한 뒤 예외를 다시 던짐
  /// - 호출하는 쪽에서는 "구글 계정 연결이 만료되었습니다. 다시 로그인 해주세요" 같은 UX를 얹으면 됨
  Future<auth.AuthClient> safeClient() async {
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
        },
        level: 'error',
        tags: const ['auth', 'google'],
      );

      // 세션을 깨끗하게 초기화
      try {
        await signOut();
      } catch (_) {
        // signOut 실패는 여기서는 추가로 던지지 않고 무시
      }

      rethrow;
    }
  }

  /// 필요 시 "지금 이 시점에서 토큰/스코프를 강제로 재검증"하고 싶을 때 사용
  ///
  /// - _client를 버리고, _ensureAuthorizedClient(forceAuthorize: true) 호출
  /// - 주로 "특히 중요한 버튼" 앞에서 한 번 호출해두면 안전함
  Future<void> refreshIfNeeded() async {
    // 기존 클라이언트 버리고, 강제로 재인증/재발급
    _client = null;
    _lastAuthorizedAt = null;

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
      _lastAuthorizedAt = null;
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
      var authorization = forceAuthorize
          ? null
          : await _user!.authorizationClient.authorizationForScopes(_scopes);

      // 없으면 새로 authorize
      authorization ??= await _user!.authorizationClient.authorizeScopes(_scopes);

      _client = authorization.authClient(scopes: _scopes);
      _lastAuthorizedAt = DateTime.now();
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

  /// ─────────────────────────────────────────
  /// Sheets / Google API 에서 토큰 만료(401 / invalid_token 등) 판단용 공통 헬퍼
  /// ─────────────────────────────────────────
  static bool isInvalidTokenError(Object e) {
    final msg = e.toString();

    // 실제 invalid_token 에러 문자열 예:
    // "Access was denied (www-authenticate header was: Bearer realm="https://accounts.google.com/", error="invalid_token")."
    if (msg.contains('invalid_token')) return true;
    if (msg.contains('Access was denied')) return true;

    // 필요하면 여기서 다른 패턴도 점진적으로 추가 가능
    // ex) if (msg.contains('401') && msg.contains('Unauthorized')) ...

    return false;
  }
}
