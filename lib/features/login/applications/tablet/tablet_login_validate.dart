import '../../../../shared/auth/account_code_number.dart';

class TabletLoginValidate {
  static String? validateCodeNumber(String codeNumber) {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    if (normalized.isEmpty) return '코드번호를 입력해주세요.';
    if (!AccountCodeNumber.isValid(normalized)) {
      return '유효한 코드번호를 입력해주세요.';
    }
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
