class TripleLoginValidate {
  /// 전화번호 유효성 검사
  /// - 공백 제거 후 숫자 10~11자리 형식인지 확인
  /// - 유효하지 않으면 오류 메시지 반환, 유효하면 null 반환
  static String? validatePhone(String phone) {
    final trimmed = phone.trim();
    final regex = RegExp(r'^[0-9]{10,11}$'); // 숫자 10~11자리

    if (trimmed.isEmpty) return '전화번호를 입력해주세요.';
    if (!regex.hasMatch(trimmed)) return '유효한 전화번호를 입력해주세요.';

    return null;
  }

  /// 비밀번호 유효성 검사
  /// - 비어 있거나 5자리 미만인 경우 오류 메시지 반환
  /// - 유효하면 null 반환
  static String? validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 5) return '비밀번호는 최소 5자 이상이어야 합니다.';

    return null;
  }
}
