/// 오프라인 로그인 전용 단순 검증 유틸
class OfflineLoginValidate {
  static String? requiredName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '이름을 입력하세요';
    return null;
  }

  static String _digitsOnly(String input) {
    final codeUnits = input.codeUnits;
    final buf = StringBuffer();
    for (final u in codeUnits) {
      if (u >= 48 && u <= 57) buf.writeCharCode(u);
    }
    return buf.toString();
  }

  static String? requiredPhone(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '전화번호를 입력하세요';
    final digits = _digitsOnly(s);
    if (digits.length < 9) return '전화번호 형식이 올바르지 않습니다';
    return null;
  }

  static String? requiredPassword(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return '비밀번호를 입력하세요';
    if (s.length < 4) return '비밀번호는 4자 이상이어야 합니다';
    return null;
  }

  /// 오프라인 모드 안내 문구(필요 시 UI에 노출)
  static const String offlineHint =
      '오프라인 모드에서는 tester / 01012345678 / 12345 조합만 로그인 가능합니다.';
}
