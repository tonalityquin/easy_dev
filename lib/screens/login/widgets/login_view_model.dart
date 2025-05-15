class LoginValidator {
  static String? validatePhone(String phone) {
    final trimmed = phone.trim();
    final regex = RegExp(r'^[0-9]{10,11}$'); // 수정됨!
    if (trimmed.isEmpty) return '전화번호를 입력해주세요.';
    if (!regex.hasMatch(trimmed)) return '유효한 전화번호를 입력해주세요.';
    return null;
  }


  static String? validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 5) return '비밀번호는 최소 5자 이상이어야 합니다.';
    return null;
  }
}
