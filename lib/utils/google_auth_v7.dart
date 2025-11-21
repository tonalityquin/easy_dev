// lib/utils/google_auth_v7.dart
//
// [호환 레이어] — 기존 코드가 google_auth_v7.dart를 참조해도
// 내부적으로 전역 세션(GoogleAuthSession)을 재사용하도록 유지.
// 여기서 한 번 refreshIfNeeded()를 호출해 최신 스코프(예: gmail.send) 재승인.

import 'package:http/http.dart' as http;
import 'google_auth_session.dart';

class GoogleAuthV7 {
  GoogleAuthV7._();

  static Future<http.Client> authedClient(List<String> _ignoredScopes) async {
    // 🔁 새 스코프가 추가된 경우 강제 재승인 시도(최초 1회만 프롬프트)
    await GoogleAuthSession.instance.refreshIfNeeded();
    return await GoogleAuthSession.instance.safeClient();
  }

  static Future<void> signOut() async {
    await GoogleAuthSession.instance.signOut();
  }
}
