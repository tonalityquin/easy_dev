// lib/utils/google_auth_v7.dart
//
// [호환 레이어] — 기존 코드가 google_auth_v7.dart를 참조해도
// 내부적으로 전역 세션(GoogleAuthSession)을 재사용하도록 변경.
// 추가 authenticate()/프롬프트 없음.

import 'package:http/http.dart' as http;
import 'google_auth_session.dart';

class GoogleAuthV7 {
  GoogleAuthV7._();

  static Future<http.Client> authedClient(List<String> _ignoredScopes) async {
    // 세션이 관리하는 AuthClient를 그대로 반환
    return await GoogleAuthSession.instance.client();
  }

  static Future<void> signOut() async {
    await GoogleAuthSession.instance.signOut();
  }
}
