// File: lib/utils/google_auth_session.dart
//
// - 중앙 OAuth 세션 (GoogleSignIn + googleapis_auth.AuthClient)
// - Debug 플래그: "구글 세션 시도 차단" ON 시 앱 전체 Google 세션/로그인 시도를 차단(SharedPreferences 저장)
//
// DebugApiLogger 경로는 실제 파일 위치에 맞게 조정되어야 합니다.
// (사용자 제공 코드 기준: utils -> screens 경로로 import)

import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth show AuthClient;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

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

class GoogleSessionBlockedException implements Exception {
  final String message;
  GoogleSessionBlockedException([this.message = '구글 세션 시도 차단(ON) 상태입니다.']);
  @override
  String toString() => message;
}

class GoogleAuthSession {
  GoogleAuthSession._();

  static final GoogleAuthSession instance = GoogleAuthSession._();

  // SharedPreferences key (전역 동일 키)
  static const String prefsKeyBlockGoogleSession = 'debug_block_google_session_attempts_v1';

  GoogleSignInAccount? _user;
  auth.AuthClient? _client;
  late List<String> _scopes;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;
  bool _initialized = false;

  /// 마지막으로 authorize(토큰/스코프 부여)에 성공한 시각
  DateTime? _lastAuthorizedAt;

  /// _client 최대 허용 수명 (TTL)
  Duration _maxClientAge = const Duration(minutes: 30);

  /// 구글 세션(로그인) 시도 차단 플래그 (prefs 영구 저장)
  bool _sessionBlocked = false;
  bool _blockFlagLoaded = false;
  Completer<void>? _blockLoadCompleter;

  /// 외부에서 현재 차단 상태 확인용 (DebugBottomSheet에서 사용)
  bool get isSessionBlocked => _sessionBlocked;

  /// 외부에서 TTL을 조절하고 싶을 때 사용
  void setMaxClientAge(Duration duration) {
    _maxClientAge = duration;
  }

  // ─────────────────────────────────────────
  // SharedPreferences 기반 차단 플래그 로딩/저장
  // ─────────────────────────────────────────

  Future<void> _ensureBlockFlagLoaded() async {
    if (_blockFlagLoaded) return;

    // 동시 호출 보호
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

  /// Debug UI에서 미리 prefs를 읽어두기 위한 메서드
  Future<void> warmUpBlockFlag() async {
    try {
      await _ensureBlockFlagLoaded();
    } catch (_) {
      // warm-up 실패는 조용히 무시 (기본 OFF로 동작)
    }
  }

  /// Debug UI에서 차단 상태를 변경(저장)하기 위한 메서드
  Future<void> setSessionBlocked(bool blocked) async {
    await _ensureBlockFlagLoaded();

    _sessionBlocked = blocked;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKeyBlockGoogleSession, blocked);

    if (blocked) {
      // 차단 ON 시: 구글 플러그인 호출을 유발할 수 있는 상태를 모두 폐기
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

  // ─────────────────────────────────────────
  // 기존 init / client 로직
  // ─────────────────────────────────────────

  Future<void> init({
    String? serverClientId,
    List<String>? additionalScopes,
  }) async {
    await _ensureBlockFlagLoaded();

    // 이미 초기화된 경우: 스코프만 merge
    if (_initialized) {
      final merged = {..._scopes, ...?additionalScopes};
      _scopes = merged.toList();
      return;
    }

    // _scopes 먼저 구성
    _scopes = {...AppScopes.all(), ...?additionalScopes}.toList();
    _initialized = true;

    // ✅ 차단 ON이면: GoogleSignIn initialize/lightweight 인증을 실행하지 않음(전역 차단)
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

  /// 내부용 AuthClient 획득 함수
  ///
  /// - 차단 ON이면 즉시 예외
  /// - TTL 이내라면 기존 _client 재사용
  /// - TTL이 지났거나 _client가 없으면 다시 authorize
  Future<auth.AuthClient> _rawClient() async {
    await _ensureBlockFlagLoaded();
    _throwIfBlocked('_rawClient');

    try {
      // 아직 init 안 되어 있으면 기본 스코프로 init
      if (!_initialized) {
        await init();
      }

      // 사용자 없으면 경량 인증 한 번 더 시도
      // (차단 ON이면 위에서 이미 예외)
      _user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();

      // TTL 체크: 너무 오래된 클라이언트는 버림
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

  /// 비즈니스 로직에서 사용하는 AuthClient 획득 함수
  ///
  /// - 차단 ON이면 즉시 예외 (구글 로그인/세션 시도 차단)
  /// - 내부적으로 _rawClient()를 호출
  /// - 실패 시 signOut까지 시도한 뒤 예외를 다시 던짐
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

  /// 필요 시 토큰/스코프를 강제로 재검증하고 싶을 때 사용
  ///
  /// - 차단 ON이면 즉시 예외
  /// - _client를 버리고, _ensureAuthorizedClient(forceAuthorize: true) 호출
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

    // ✅ 차단 ON이면: 플러그인 호출을 피하고 로컬 상태만 정리
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

      authorization ??= await _user!.authorizationClient.authorizeScopes(_scopes);

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

  /// ─────────────────────────────────────────
  /// Sheets / Google API 에서 토큰 만료(401 / invalid_token 등) 판단용 공통 헬퍼
  /// ─────────────────────────────────────────
  static bool isInvalidTokenError(Object e) {
    final msg = e.toString();

    if (msg.contains('invalid_token')) return true;
    if (msg.contains('Access was denied')) return true;

    return false;
  }
}
