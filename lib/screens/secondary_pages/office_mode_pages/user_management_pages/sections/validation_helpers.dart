typedef ValidationRule = String Function(String value);

final Map<String, ValidationRule> validationRules = {
  '이름': (value) => value.isEmpty ? '이름을 다시 입력하세요' : '',
  '전화번호': (value) =>
  RegExp(r'^\d{9,}$').hasMatch(value) ? '' : '전화번호를 다시 입력하세요',
  '이메일': (value) => value.isEmpty ? '이메일을 입력하세요' : '',
};

String? validateInputs(Map<String, String> inputs) {
  for (var entry in validationRules.entries) {
    final field = entry.key;
    final validator = entry.value;
    final value = inputs[field] ?? '';
    final result = validator(value);
    if (result.isNotEmpty) return result;
  }
  return null;
}
