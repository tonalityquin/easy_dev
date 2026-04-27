import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

String _firebaseBridgeTs() => DateTime.now().toIso8601String();

class FirebaseGoogleAuthBridge {
  FirebaseGoogleAuthBridge._();

  static final FirebaseGoogleAuthBridge instance = FirebaseGoogleAuthBridge._();

  static const bool _enableDebugAnonymousFallback = bool.fromEnvironment(
    'PW_FIREBASE_AUTH_DEV_ANON_FALLBACK',
    defaultValue: false,
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _runtimeConfigured = false;

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => _auth.currentUser != null;

  bool get canUseProductionAnonymousFallback =>
      kDebugMode && _enableDebugAnonymousFallback;

  Future<void> configureRuntime() async {
    if (_runtimeConfigured) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] configureRuntime skipped: already configured',
      );
      return;
    }

    _runtimeConfigured = true;

    debugPrint(
      '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] FirebaseAuth production runtime 사용 productionAnonFallback=$canUseProductionAnonymousFallback',
    );
  }


  Future<bool> bootstrapWithExistingGoogleUser(
    GoogleSignInAccount? googleUser,
  ) async {
    await configureRuntime();

    debugPrint(
      '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] bootstrapWithExistingGoogleUser start googleEmail=${googleUser?.email} productionAnonFallback=$canUseProductionAnonymousFallback',
    );

    if (googleUser == null) {
      if (canUseProductionAnonymousFallback) {
        final ok = await _signInAnonymouslyForDebug();
        final user = _auth.currentUser;
        debugPrint(
          '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] bootstrapWithExistingGoogleUser anon result ok=$ok uid=${user?.uid} email=${user?.email} anonymous=${user?.isAnonymous}',
        );
        return ok;
      }

      final user = _auth.currentUser;
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] bootstrapWithExistingGoogleUser no-google-user result ok=false uid=${user?.uid} email=${user?.email} anonymous=${user?.isAnonymous}',
      );
      return false;
    }

    final ok = await ensureSignedInWithGoogleUser(googleUser);
    final user = _auth.currentUser;
    debugPrint(
      '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] bootstrapWithExistingGoogleUser result ok=$ok uid=${user?.uid} email=${user?.email} anonymous=${user?.isAnonymous}',
    );
    return ok;
  }

  Future<bool> bootstrap({bool interactive = false}) async {
    await configureRuntime();
    final ok = await ensureSignedInFromGoogleSession(interactive: interactive);
    final user = _auth.currentUser;
    debugPrint(
      '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] bootstrap result ok=$ok uid=${user?.uid} email=${user?.email} anonymous=${user?.isAnonymous}',
    );
    return ok;
  }

  Future<bool> ensureSignedInFromGoogleSession({bool interactive = false}) async {
    await configureRuntime();

    final existing = _auth.currentUser;
    if (existing != null && !existing.isAnonymous) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] 기존 Firebase 사용자 유지 uid=${existing.uid} email=${existing.email}',
      );
      return true;
    }

    GoogleSignInAccount? googleUser;

    try {
      googleUser = await GoogleSignIn.instance.attemptLightweightAuthentication();
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] lightweight Google 세션 email=${googleUser?.email}',
      );
    } catch (e, st) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] lightweight Google 세션 확인 실패: $e\n$st',
      );
    }

    if (googleUser == null &&
        interactive &&
        GoogleSignIn.instance.supportsAuthenticate()) {
      try {
        debugPrint(
          '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] interactive Google 인증 시도',
        );
        googleUser = await GoogleSignIn.instance.authenticate();
        debugPrint(
          '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] interactive Google 인증 결과 email=${googleUser.email}',
        );
      } catch (e, st) {
        debugPrint(
          '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] interactive Google 인증 실패: $e\n$st',
        );
      }
    }

    if (googleUser == null) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Google 세션 없음 interactive=$interactive productionAnonFallback=$canUseProductionAnonymousFallback',
      );
      if (canUseProductionAnonymousFallback) {
        return _signInAnonymouslyForDebug();
      }
      return false;
    }

    return ensureSignedInWithGoogleUser(googleUser);
  }

  Future<bool> ensureSignedInWithGoogleUser(
    GoogleSignInAccount? googleUser,
  ) async {
    await configureRuntime();

    if (googleUser == null) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] ensureSignedInWithGoogleUser skipped: googleUser=null',
      );
      return false;
    }

    final current = _auth.currentUser;
    final normalizedGoogleEmail = googleUser.email.trim().toLowerCase();
    final normalizedCurrentEmail = current?.email?.trim().toLowerCase();

    if (current != null &&
        !current.isAnonymous &&
        normalizedCurrentEmail == normalizedGoogleEmail) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Firebase 사용자와 Google 사용자 이메일 일치 email=$normalizedGoogleEmail',
      );
      return true;
    }

    try {
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Google 인증 정보 수신 email=${googleUser.email} hasIdToken=${idToken != null && idToken.isNotEmpty}',
      );

      if (idToken == null || idToken.isEmpty) {
        debugPrint(
          '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] FirebaseAuth 로그인 중단: idToken 없음',
        );
        return false;
      }

      if (current != null && current.isAnonymous) {
        debugPrint(
          '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] 익명 Firebase 세션 정리 후 Google credential 로그인 진행',
        );
        await _auth.signOut();
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;

      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] FirebaseAuth Google 로그인 성공 uid=${user?.uid} email=${user?.email} anonymous=${user?.isAnonymous}',
      );

      return user != null;
    } catch (e, st) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] FirebaseAuth Google 로그인 실패 email=${googleUser.email}: $e\n$st',
      );
      return false;
    }
  }

  Future<bool> _signInAnonymouslyForDebug() async {
    final current = _auth.currentUser;
    if (current != null && current.isAnonymous) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] production 익명 Firebase 세션 재사용 uid=${current.uid}',
      );
      return true;
    }

    try {
      final result = await _auth.signInAnonymously();
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] production 익명 Firebase 로그인 성공 uid=${result.user?.uid}',
      );
      return result.user != null;
    } catch (e, st) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] production 익명 Firebase 로그인 실패: $e\n$st',
      );
      return false;
    }
  }

  Future<void> signOutFirebaseOnly() async {
    await configureRuntime();

    final current = _auth.currentUser;
    if (current == null) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] signOutFirebaseOnly skipped: currentUser=null',
      );
      return;
    }

    debugPrint(
      '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Firebase 로그아웃 uid=${current.uid} email=${current.email} anonymous=${current.isAnonymous}',
    );

    await _auth.signOut();

    debugPrint(
      '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Firebase 로그아웃 완료',
    );
  }

  Future<void> signOutAll() async {
    await signOutFirebaseOnly();

    try {
      await GoogleSignIn.instance.signOut();
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Google 로그아웃 완료',
      );
    } catch (e, st) {
      debugPrint(
        '[FB-AUTH-BRIDGE][${_firebaseBridgeTs()}] Google 로그아웃 실패: $e\n$st',
      );
    }
  }
}
