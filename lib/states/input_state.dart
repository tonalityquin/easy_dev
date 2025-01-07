import 'package:flutter/material.dart';

class InputState with ChangeNotifier {
  // 필드 키 상수화
  static const String FRONT_3 = 'front3';
  static const String MIDDLE_1 = 'middle1';
  static const String BACK_4 = 'back4';

  final Map<String, String> _inputFields = {
    FRONT_3: '', // 앞 3자리
    MIDDLE_1: '', // 중간 1자리
    BACK_4: '', // 뒤 4자리
  };

  // Getter
  String get front3 => _inputFields[FRONT_3] ?? '';
  String get middle1 => _inputFields[MIDDLE_1] ?? '';
  String get back4 => _inputFields[BACK_4] ?? '';

  // 필드 업데이트
  void updateField(String field, String value) {
    if (_inputFields.containsKey(field)) {
      _inputFields[field] = value;
      notifyListeners();
    } else {
      throw ArgumentError('Invalid field name: $field');
    }
  }

  // 입력값 초기화
  void clearInput() {
    _inputFields.updateAll((key, value) => '');
    notifyListeners();
  }

  // 입력값 유효성 검사
  bool isValidField(String field, String value) {
    switch (field) {
      case FRONT_3:
      case BACK_4:
        return RegExp(r'^\d{0,3}$').hasMatch(value); // 최대 3자리 숫자
      case MIDDLE_1:
        return RegExp(r'^\d{0,1}$').hasMatch(value); // 최대 1자리 숫자
      default:
        return false;
    }
  }

  // 유효성 검사와 함께 필드 업데이트
  void updateFieldWithValidation(String field, String value) {
    if (!_inputFields.containsKey(field)) {
      debugPrint('Error: Invalid field name: $field');
      throw ArgumentError('Invalid field name: $field');
    }

    if (!isValidField(field, value)) {
      debugPrint('Error: Invalid value for field $field: $value');
      throw ArgumentError('Invalid value for field $field: $value');
    }

    updateField(field, value);
  }
}
