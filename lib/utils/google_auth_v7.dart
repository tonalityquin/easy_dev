// lib/utils/google_auth_v7.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

/// google_sign_in v7 전용 OAuth 헬퍼
/// - v7에서는 기본 생성자가 없고, GoogleSignIn.instance 를 사용합니다.
/// - requestScopes() / signInSilently() 등이 사라졌고,
///   authenticate() / attemptLightweightAuthentication() / authorizationClient.* 를 사용합니다.
class GoogleAuthV7 {
  GoogleAuthV7._();

  /// (필요 시) 클라이언트 ID를 지정할 수 있습니다.
  static String? clientId;        // iOS/웹 등 클라이언트 ID
  static String? serverClientId;  // Android/서버 인증 코드 용

  static bool _inited = false;
  static GoogleSignInAccount? _cachedUser;

  // 스코프 세트별 http.Client 캐시 (중복 생성 방지)
  static final Map<String, http.Client> _clientCache = {};

  /// 초기화 (앱 시작 시 1회 권장)
  static Future<void> init({
    String? clientId,
    String? serverClientId,
    List<String> preauthorizeScopes = const [],
  }) async {
    GoogleAuthV7.clientId = clientId ?? GoogleAuthV7.clientId;
    GoogleAuthV7.serverClientId = serverClientId ?? GoogleAuthV7.serverClientId;
    await _ensureInitialized();
    if (preauthorizeScopes.isNotEmpty) {
      // 미리 한 번 승인 받아두면, 이후 팝업 없음
      await ensureAuthorized(preauthorizeScopes);
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_inited) return;
    await GoogleSignIn.instance.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
    _inited = true;
  }

  /// 사용자 인증: 기존 세션을 가볍게 복원 → 실패 시 인터랙티브 인증(가능한 플랫폼 한정)
  static Future<GoogleSignInAccount> _ensureSignedIn() async {
    await _ensureInitialized();

    // 캐시된 사용자 있으면 재사용
    if (_cachedUser != null) return _cachedUser!;

    // 기존 인증 복원
    final restored = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (restored != null) {
      _cachedUser = restored;
      return restored;
    }

    // 플랫폼이 authenticate()를 지원하면 사용자 제스처 안에서 호출하세요.
    if (GoogleSignIn.instance.supportsAuthenticate()) {
      final user = await GoogleSignIn.instance.authenticate();
      _cachedUser = user;
      return user;
    }

    throw StateError(
      'GoogleSignIn.authenticate() is not supported on this platform.',
    );
  }

  /// 주어진 scopes에 대해 Authorization 헤더를 돌려줍니다.
  /// - 내부에서 토큰을 갱신/요청하고, 필요하면 사용자에게 승인 프롬프트를 띄웁니다.
  static Future<Map<String, String>> _authorizedHeaders(
      List<String> scopes,
      ) async {
    final user = await _ensureSignedIn();

    // 편의 메서드: authorizationHeaders (promptIfNecessary: true)
    //  - 이미 승인된 경우 바로 헤더 반환
    //  - 미승인된 경우 사용자에게 프롬프트 후 헤더 반환
    final headers = await user.authorizationClient
        .authorizationHeaders(scopes, promptIfNecessary: true);

    if (headers == null || headers.isEmpty) {
      throw StateError('Failed to obtain authorization headers.');
    }
    return headers;
  }

  /// 사전 승인(프리워밍) — 앱 초기화 시 한 번 호출하면 이후 팝업 제거에 도움
  static Future<void> ensureAuthorized(List<String> scopes) async {
    await _authorizedHeaders(scopes);
  }

  /// googleapis 패키지와 함께 사용할 수 있도록 Authorization 헤더를
  /// 매 요청마다 붙여주는 http.Client 래퍼를 제공합니다.
  /// - 스코프 세트별로 Client를 캐시하여 중복 생성을 방지합니다.
  static Future<http.Client> authedClient(List<String> scopes) async {
    final key = scopes.toSet().toList()..sort();
    final cacheKey = key.join(' ');
    final existed = _clientCache[cacheKey];
    if (existed != null) return existed;

    final base = http.Client();
    final wrapped = _HeaderClient(
      base: base,
      headersProvider: () => _authorizedHeaders(scopes),
    );
    _clientCache[cacheKey] = wrapped;
    return wrapped;
  }

  /// 로그아웃 및 캐시 정리
  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    _cachedUser = null;
    for (final c in _clientCache.values) {
      try {
        c.close();
      } catch (_) {}
    }
    _clientCache.clear();
  }
}

/// 매 요청 전에 최신 Authorization 헤더를 붙이는 Client
class _HeaderClient extends http.BaseClient {
  _HeaderClient({
    required this.base,
    required this.headersProvider,
  });

  final http.Client base;
  final Future<Map<String, String>> Function() headersProvider;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await headersProvider();
    request.headers.addAll(headers);
    return base.send(request);
  }

  @override
  void close() => base.close();
}
