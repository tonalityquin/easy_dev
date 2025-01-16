import 'package:flutter/material.dart';

/// **InputState 클래스**
/// - 차량 번호판 입력 필드의 상태를 관리
/// - 입력 필드의 값 업데이트, 검증, 초기화 기능 제공
class InputState with ChangeNotifier {
  /// **필드 이름 상수 정의**
  static const String front_3 = 'front3'; // 차량 번호판 앞 3자리 필드
  static const String middle_1 = 'middle1'; // 번호판 중간 1자리 필드
  static const String back_4 = 'back4'; // 번호판 뒤 4자리 필드

  /// **필드별 유효성 검사 규칙**
  final Map<String, RegExp> _validationRules = {
    front_3: RegExp(r'^\d{0,3}$'),
    middle_1: RegExp(r'^\d{0,1}$'),
    back_4: RegExp(r'^\d{0,4}$'),
  };

  /// **입력 필드 값을 저장하는 내부 맵**
  final Map<String, String> _inputFields = {
    front_3: '',
    middle_1: '',
    back_4: '',
  };

  /// **필드 값 읽기**
  String get front3 => _inputFields[front_3] ?? '';

  String get middle1 => _inputFields[middle_1] ?? '';

  String get back4 => _inputFields[back_4] ?? '';

  /// **필드 값을 업데이트하고 상태 변경 알림**
  void updateField(String field, String value) {
    if (_inputFields.containsKey(field)) {
      _inputFields[field] = value;
      notifyListeners();
    } else {
      throw ArgumentError('Invalid field name: $field');
    }
  }

  /// **필드 유효성 검사**
  bool isValidField(String field, String value) {
    return _validationRules[field]?.hasMatch(value) ?? false;
  }

  /// **유효성 검증 후 필드 업데이트**
  void updateFieldWithValidation(String field, String value, {void Function(String)? onError}) {
    if (!isValidField(field, value)) {
      final error = 'Invalid value for field $field: $value';
      debugPrint(error);
      if (onError != null) onError(error);
      return;
    }
    updateField(field, value);
  }

  /// **모든 입력 필드 초기화**
  void clearInput() {
    _inputFields.updateAll((key, value) => '');
    notifyListeners();
  }
}
