import '../../../../shared/auth/account_code_number.dart';

class DoubleLoginValidate {
  static String? validateCodeNumber(String codeNumber) {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    if (normalized.isEmpty) return '코드번호를 입력해주세요.';
    if (!AccountCodeNumber.isValid(normalized)) {
      return '유효한 코드번호를 입력해주세요.';
    }
    return null;
  }


  static String? validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 5) return '비밀번호는 최소 5자 이상이어야 합니다.';
    return null;
  }
}
