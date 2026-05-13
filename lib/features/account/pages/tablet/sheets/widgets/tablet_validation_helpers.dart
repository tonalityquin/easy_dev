typedef ValidationRule = String Function(String value);

final Map<String, ValidationRule> _tabletValidationRules = {
  '이름': (value) => value.trim().isEmpty ? '이름을 다시 입력하세요' : '',
  '아이디': (value) => RegExp(r'^[a-z]{3,20}$').hasMatch(value.trim())
      ? ''
      : '아이디는 소문자 영어 3~20자로 입력하세요',
  '이메일': (value) => value.trim().isEmpty ? '이메일을 입력하세요' : '',
};

String? validateTabletInputs(Map<String, String> inputs) {
  for (final entry in _tabletValidationRules.entries) {
    final field = entry.key;
    final validator = entry.value;
    final value = inputs[field] ?? '';
    final result = validator(value);
    if (result.isNotEmpty) return result;
  }
  return null;
}
