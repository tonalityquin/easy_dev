import 'package:flutter/material.dart';

/// **InputState 클래스**
/// - 차량 번호판 입력 필드의 상태를 관리
/// - 입력 필드의 값 업데이트, 검증, 초기화 기능 제공
class InputState with ChangeNotifier {
  /// **필드 이름 상수 정의**
  static const String front_3 = 'front3'; // 차량 번호판 앞 3자리 필드
  static const String middle_1 = 'middle1'; // 번호판 중간 1자리 필드
  static const String back_4 = 'back4'; // 번호판 뒤 4자리 필드

  /// **필드 목록 정의**
  /// - 자동화를 위해 모든 필드를 리스트로 관리
  final List<String> _fields = [front_3, middle_1, back_4];

  /// **필드별 유효성 검사 규칙**
  final Map<String, RegExp> _validationRules = {
    front_3: RegExp(r'^\d{0,3}$'), // 3자리 숫자까지 입력 허용
    middle_1: RegExp(r'^\d{0,1}$'), // 1자리 숫자까지 입력 허용
    back_4: RegExp(r'^\d{0,4}$'), // 4자리 숫자까지 입력 허용
  };

  /// **입력 필드 값을 저장하는 내부 맵**
  late final Map<String, String> _inputFields = {
    for (var field in _fields) field: '', // 필드 리스트를 기반으로 초기화
  };

  /// **필드 값 읽기**
  String get front3 => _inputFields[front_3] ?? '';
  String get middle1 => _inputFields[middle_1] ?? '';
  String get back4 => _inputFields[back_4] ?? '';

  /// **필드 값을 업데이트하고 상태 변경 알림**
  void updateField(String field, String value) {
    if (!_inputFields.containsKey(field)) {
      final error = '🚨 Invalid field name: $field';
      debugPrint(error);
      return;
    }
    _inputFields[field] = value;
    notifyListeners();
  }


  /// **필드 유효성 검사**
  bool isValidField(String field, String value) {
    return _validationRules[field]?.hasMatch(value) ?? false;
  }

  /// **유효성 검증 후 필드 업데이트**
  void updateFieldWithValidation(String field, String value, {required void Function(String) onError}) {
    if (!isValidField(field, value)) {
      final error = '🚨 Invalid value for field $field: $value';
      debugPrint(error);
      onError(error);
      return;
    }
    updateField(field, value);
  }


  /// **모든 입력 필드 초기화**
  void clearInput() {
    bool hasChanged = false;
    _inputFields.forEach((key, value) {
      if (value.isNotEmpty) {
        _inputFields[key] = '';
        hasChanged = true;
      }
    });

    if (hasChanged) {
      notifyListeners(); // 🚀 값이 변경된 경우에만 UI 업데이트
    }
  }
}
