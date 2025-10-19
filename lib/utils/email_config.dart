// lib/utils/email_config.dart
//
// 경위서 제출 시 사용할 Gmail 수신자 설정을 로컬(SharedPreferences)에 저장/로드.
// - 저장 키: 'mail.to'
// - 기본값: 수신자(To)는 빈 값("")  ← 사용자가 직접 채워야 전송 가능
// - 여러 수신자 입력: 쉼표(,)로 구분

import 'package:shared_preferences/shared_preferences.dart';

class EmailConfig {
  final String to; // "a@x.com, b@y.com" 형태의 CSV

  const EmailConfig({required this.to});

  static const _kMailToKey = 'mail.to';

  // 기본값 — 비어 있음
  static String _defaultTo() => '';

  static Future<EmailConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final to = (prefs.getString(_kMailToKey) ?? _defaultTo()).trim();
    return EmailConfig(to: to);
  }

  static Future<void> save(EmailConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMailToKey, cfg.to.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMailToKey, _defaultTo());
  }

  // 간단한 이메일 리스트 검증(쉼표 분리 후 각 항목의 형식 확인)
  static bool isValidToList(String csv) {
    final list = csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    if (list.isEmpty) return false;
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    for (final addr in list) {
      if (!regex.hasMatch(addr)) return false;
    }
    return true;
  }
}
