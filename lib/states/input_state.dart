import 'package:flutter/material.dart';

/// **InputState 클래스**
/// - 차량 번호판 입력 필드의 상태를 관리
/// - 입력 필드의 값 업데이트, 검증, 초기화 기능 제공
class InputState with ChangeNotifier {
  /// **필드 이름 상수 정의**
  static const String front_3 = 'front3'; // 차량 번호판 앞 3자리 필드
  static const String middle_1 = 'middle1'; // 번호판 중간 1자리 필드
  static const String back_4 = 'back4'; // 번호판 뒤 4자리 필드

  /// **입력 필드 값을 저장하는 내부 맵**
  /// - 키: 필드 이름 (front3, middle1, back4)
  /// - 값: 각 필드에 입력된 문자열 값
  final Map<String, String> _inputFields = {
    front_3: '', // 앞 3자리 초기값
    middle_1: '', // 중간 1자리 초기값
    back_4: '', // 뒤 4자리 초기값
  };

  /// **입력 필드 값 읽기용 getter**
  /// - `front3`: 앞 3자리 필드 값
  /// - `middle1`: 중간 1자리 필드 값
  /// - `back4`: 뒤 4자리 필드 값
  String get front3 => _inputFields[front_3] ?? '';

  String get middle1 => _inputFields[middle_1] ?? '';

  String get back4 => _inputFields[back_4] ?? '';

  /// **필드 값을 업데이트하고 상태 변경 알림**
  /// - [field]: 필드 이름 (front3, middle1, back4 중 하나)
  /// - [value]: 새로 업데이트할 값
  /// - 상태 변경 후 `notifyListeners()` 호출
  void updateField(String field, String value) {
    if (_inputFields.containsKey(field)) {
      _inputFields[field] = value; // 필드 값 업데이트
      notifyListeners(); // 상태 변경 알림
    } else {
      throw ArgumentError('Invalid field name: $field'); // 유효하지 않은 필드 이름 예외 처리
    }
  }

  /// **모든 입력 필드를 초기화**
  /// - 모든 필드 값을 빈 문자열로 설정
  /// - 상태 변경 후 `notifyListeners()` 호출
  void clearInput() {
    _inputFields.updateAll((key, value) => ''); // 모든 필드 값 초기화
    notifyListeners(); // 상태 변경 알림
  }

  /// **특정 필드의 값 유효성 검사**
  /// - [field]: 필드 이름
  /// - [value]: 검증할 값
  /// - 반환값: 유효한 경우 `true`, 그렇지 않으면 `false`
  bool isValidField(String field, String value) {
    switch (field) {
      case front_3:
      case back_4:
        // 앞 3자리 및 뒤 4자리는 최대 3자리 숫자 검증
        return RegExp(r'^\d{0,3}$').hasMatch(value);
      case middle_1:
        // 중간 1자리는 최대 1자리 숫자 검증
        return RegExp(r'^\d{0,1}$').hasMatch(value);
      default:
        return false; // 유효하지 않은 필드 이름
    }
  }

  /// **필드 값 검증 후 업데이트**
  /// - [field]: 필드 이름
  /// - [value]: 업데이트할 값
  /// - 검증 실패 시 예외 발생
  void updateFieldWithValidation(String field, String value) {
    if (!_inputFields.containsKey(field)) {
      debugPrint('Error: Invalid field name: $field'); // 디버그 로그 출력
      throw ArgumentError('Invalid field name: $field'); // 유효하지 않은 필드 이름 예외 처리
    }

    if (!isValidField(field, value)) {
      debugPrint('Error: Invalid value for field $field: $value'); // 디버그 로그 출력
      throw ArgumentError('Invalid value for field $field: $value'); // 유효하지 않은 값 예외 처리
    }

    updateField(field, value); // 검증 성공 시 필드 값 업데이트
  }
}
