import '../../../../../../shared/auth/account_code_number.dart';

typedef ValidationRule = String Function(String value);

final Map<String, ValidationRule> validationRules = {
  '이름': (value) => value.isEmpty ? '이름을 다시 입력하세요' : '',
  '코드번호': (value) => AccountCodeNumber.isValid(value)
      ? ''
      : '코드번호를 다시 확인하세요',
  '이메일': (value) => value.isEmpty ? '이메일을 입력하세요' : '',
};

String? validateInputs(Map<String, String> inputs) {
  for (final entry in validationRules.entries) {
    final value = inputs[entry.key] ?? '';
    final result = entry.value(value);
    if (result.isNotEmpty) return result;
  }
  return null;
}
