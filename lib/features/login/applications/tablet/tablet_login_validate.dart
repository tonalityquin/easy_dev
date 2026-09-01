class TabletLoginValidate {
  static String? validatePhone(String phone) {
    final trimmed = phone.trim();
    final regex = RegExp(r'^[0-9]{10,11}$');
    if (trimmed.isEmpty) return '전화번호를 입력해주세요.';
    if (!regex.hasMatch(trimmed)) return '유효한 전화번호를 입력해주세요.';
    return null;
  }

  static String? validatePassword(String password) {
    final trimmed = password.trim();
    if (trimmed.isEmpty) return '비밀번호를 입력해주세요.';
    if (!RegExp(r'^\d{5}$').hasMatch(trimmed)) {
      return '비밀번호는 5자리 숫자로 입력해주세요.';
    }
    return null;
  }
}
