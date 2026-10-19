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
}
