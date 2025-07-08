typedef ValidationRule = String Function(String value);

/// 각 필드에 대한 유효성 검사 함수 매핑
final Map<String, ValidationRule> validationRules = {
  '이름': (value) => value.isEmpty ? '이름을 다시 입력하세요' : '',
  '전화번호': (value) =>
  RegExp(r'^\d{9,}$').hasMatch(value) ? '' : '전화번호를 다시 입력하세요',
  '이메일': (value) => value.isEmpty ? '이메일을 입력하세요' : '',
};

/// 입력값을 기반으로 유효성 검사 수행
///
/// [inputs]는 key가 필드 이름, value가 입력값인 Map
/// 유효하지 않은 경우 첫 번째 오류 메시지를 반환하고,
/// 유효한 경우 null 반환
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
