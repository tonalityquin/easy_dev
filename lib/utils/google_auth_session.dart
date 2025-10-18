// lib/utils/google_auth_session.dart
//
// Google 계정 인증을 앱 전역에서 "최초 1회"만 수행하고,
// 이후 Calendar / Sheets / Docs / GCS 등 모든 기능이 동일한 AuthClient를 재사용하도록 하는 세션.
// google_sign_in v7 API에 맞춰 작성됨.
//
// 의존 패키지(pubspec.yaml 예시):
//   google_sign_in: ^7.2.0
//   extension_google_sign_in_as_googleapis_auth: ^3.0.0
//   googleapis_auth: ^1.5.0
//
// 사용법:
//  1) 앱 시작 시 단 한 번:
//       await GoogleAuthSession.instance.init(serverClientId: kWebClientId);
//  2) 각 서비스에서:
//       final client = await GoogleAuthSession.instance.client();
//       final sheets = sheets_api.SheetsApi(client); // 등등
//
// 참고 (v7 변경점):
//  - onCurrentUserChanged -> authenticationEvents (스트림)  [v7 문서 참고]
//  - signInSilently      -> attemptLightweightAuthentication()
//  - requestScopes       -> authorizationClient.authorizeScopes(scopes)
//  - AuthClient 생성은 GoogleSignInAccount가 아닌
//    GoogleSignInClientAuthorization에 확장된 authClient(scopes: ...)로 수행
//
// 웹의 경우 authorizeScopes는 사용자 행동(버튼 클릭) 문맥에서 호출돼야 할 수 있음.
// 모바일(Android/iOS)은 init()에서 호출해도 동작합니다.

import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth show AuthClient;
// 확장 메서드: GoogleSignInClientAuthorization.authClient(...)
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class AppScopes {
  // 앱에서 실제 사용하는 Google API 스코프를 합집합으로 선언하세요.
  static const String calendarEvents =
      'https://www.googleapis.com/auth/calendar.events';
  static const String spreadsheets =
      'https://www.googleapis.com/auth/spreadsheets';
  static const String documents =
      'https://www.googleapis.com/auth/documents';
  // GCS 접근이 필요할 때(쓰기 포함)
  static const String gcsReadWrite =
      'https://www.googleapis.com/auth/devstorage.read_write';
  // (선택) Drive 파일 생성/소유가 꼭 필요할 때만 사용
  // static const String driveFile =
  //     'https://www.googleapis.com/auth/drive.file';

  static List<String> all() => <String>{
    calendarEvents,
    spreadsheets,
    documents,
    gcsReadWrite,
    // driveFile,
  }.toList();
}

class GoogleAuthSession {
  GoogleAuthSession._();
  static final GoogleAuthSession instance = GoogleAuthSession._();

  // 상태
  GoogleSignInAccount? _user;
  auth.AuthClient? _client;
  late List<String> _scopes;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;
  bool _initialized = false;

  /// 앱 시작 시 한 번 호출 (Splash/앱 초기화 지점)
  Future<void> init({
    String? serverClientId,
    List<String>? additionalScopes,
  }) async {
    if (_initialized) return;
    _initialized = true;

    // 스코프 준비(중복 제거)
    _scopes = {...AppScopes.all(), ...?additionalScopes}.toList();

    // v7: 싱글턴 인스턴스 초기화
    final signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: serverClientId);

    // v7: 인증 이벤트 구독 (sign-in / sign-out)
    _authSub?.cancel();
    _authSub = signIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _user = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _user = null;
        _client = null;
      }
    });

    // 이전 로그인 세션을 조용히 복구 (가능한 최소 상호작용)
    _user = await signIn.attemptLightweightAuthentication();

    // 최초 실행 등으로 _user가 없으면, 명시적 인증 흐름(모바일은 OK)
    if (_user == null && signIn.supportsAuthenticate()) {
      try {
        await signIn.authenticate(); // 사용자에게 한 번만 UI 표시
        // 성공 시 authenticationEvents를 통해 _user가 채워집니다.
      } catch (e) {
        _initialized = false; // 재시도 허용
        rethrow;
      }
    }

    // 스코프 동의 및 AuthClient 생성
    await _ensureAuthorizedClient();
  }

  /// 공통 AuthClient 제공 (없으면 자동 재구성)
  Future<auth.AuthClient> client() async {
    if (_client != null) return _client!;
    if (!_initialized) {
      await init();
      if (_client != null) return _client!;
    }
    // 혹시 user가 비어 있다면(앱 재개 등) 복구 시도
    if (_user == null) {
      await GoogleSignIn.instance.attemptLightweightAuthentication();
    }
    await _ensureAuthorizedClient();
    if (_client == null) {
      throw StateError('AuthClient 생성 실패: 로그인 또는 스코프 권한을 확인하세요.');
    }
    return _client!;
  }

  /// 401/권한오류 등에서 호출해 재구성
  Future<void> refreshIfNeeded() async {
    _client = null;
    await _ensureAuthorizedClient(forceAuthorize: true);
  }

  /// (선택) 명시적 로그아웃
  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _user = null;
    _client = null;
  }

  /// (선택) 현재 로그인 사용자
  GoogleSignInAccount? get currentUser => _user;

  /// (선택) 현재 부여된 스코프
  List<String> get grantedScopes => List.unmodifiable(_scopes);

  // 내부: 스코프 동의와 AuthClient 구성
  Future<void> _ensureAuthorizedClient({bool forceAuthorize = false}) async {
    if (_user == null) return;

    // v7: authorizationForScopes()로 조용히 토큰 요청, 없으면 authorizeScopes()로 동의 요청
    var authorization = forceAuthorize
        ? null
        : await _user!.authorizationClient.authorizationForScopes(_scopes);

    authorization ??= await _user!.authorizationClient.authorizeScopes(_scopes);

    // extension_google_sign_in_as_googleapis_auth: authClient(scopes: ...)
    _client = authorization.authClient(scopes: _scopes);
  }

  // 리소스 정리
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
  }
}
