import 'package:flutter/material.dart';

/// **입력 필드 Enum 정의**
enum InputField { front3, middle1, back4 }

/// **InputState 클래스**
/// - 차량 번호판 입력 필드의 상태를 관리
/// - 입력 필드의 값 업데이트, 검증, 초기화 기능 제공
class InputState with ChangeNotifier {
  /// **입력 필드 목록**
  final List<InputField> _fields = InputField.values;

  /// **입력 필드별 유효성 검사 규칙**
  final Map<InputField, RegExp> _validationRules = {
    InputField.front3: RegExp(r'^\d{0,3}$'), // 3자리 숫자까지 입력 허용
    InputField.middle1: RegExp(r'^\d{0,1}$'), // 1자리 숫자까지 입력 허용
    InputField.back4: RegExp(r'^\d{0,4}$'), // 4자리 숫자까지 입력 허용
  };

  /// **입력 필드 값을 저장하는 내부 맵**
  late final Map<InputField, String> _inputFields = {
    for (var field in _fields) field: '', // 필드 리스트를 기반으로 초기화
  };

  /// **필드 값 읽기**
  String get front3 => _inputFields[InputField.front3] ?? '';

  String get middle1 => _inputFields[InputField.middle1] ?? '';

  String get back4 => _inputFields[InputField.back4] ?? '';

  /// **필드 값을 업데이트하고 상태 변경 알림**
  void updateField(InputField field, String value) {
    if (_inputFields[field] == value) return; // 값이 동일하면 업데이트하지 않음
    _inputFields[field] = value;
    notifyListeners();
  }

  /// **필드 유효성 검사**
  bool isValidField(InputField field, String value) {
    if (value.isEmpty) return true; // 🔹 빈 값은 항상 유효 (입력 초기화 가능)
    return _validationRules[field]?.hasMatch(value) ?? false;
  }

  /// **유효성 검증 후 필드 업데이트**
  void updateFieldWithValidation(InputField field, String value, {required void Function(String) onError}) {
    if (!isValidField(field, value)) {
      final error = '⚠️ 잘못된 값 입력 ($field): $value';
      debugPrint(error);
      onError(error);
      return;
    }
    updateField(field, value);
  }

  /// **모든 입력 필드 초기화**
  void clearInput() {
    bool hasChanged = false;

    _inputFields.updateAll((key, value) {
      if (value.isNotEmpty) {
        hasChanged = true;
        return '';
      }
      return value;
    });

    if (hasChanged) {
      notifyListeners(); // 🚀 값이 변경된 경우에만 UI 업데이트
    }
  }
}
