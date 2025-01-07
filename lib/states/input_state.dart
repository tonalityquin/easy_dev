import 'package:flutter/material.dart';

/// 상태 관리를 담당하는 InputState 클래스
/// 차량 번호판 입력 필드의 상태를 관리하며, 필드의 업데이트와 검증 기능을 포함
class InputState with ChangeNotifier {
  /// 필드 이름 상수 정의
  static const String front_3 = 'front3'; // 차량 번호판 앞 3자리 필드
  static const String middle_1 = 'middle1'; // 번호판 중간 1자리 필드
  static const String back_4 = 'back4'; // 번호판 뒤 4자리 필드

  /// 입력 필드를 저장하는 내부 맵
  /// 키: 필드 이름, 값: 입력된 문자열 값
  final Map<String, String> _inputFields = {
    front_3: '',
    middle_1: '',
    back_4: '',
  };

  /// 각 필드의 값을 읽기 위한 getter
  String get front3 => _inputFields[front_3] ?? ''; // 앞 3자리 값
  String get middle1 => _inputFields[middle_1] ?? ''; // 중간 1자리 값
  String get back4 => _inputFields[back_4] ?? ''; // 뒤 4자리 값

  /// 필드 값을 업데이트하고 상태 변경 알림
  /// @param field - 필드 이름 (front3, middle1, back4 중 하나)
  /// @param value - 새로운 값
  void updateField(String field, String value) {
    if (_inputFields.containsKey(field)) {
      _inputFields[field] = value; // 필드 값 업데이트
      notifyListeners(); // 상태 변경 알림
    } else {
      throw ArgumentError('Invalid field name: $field'); // 유효하지 않은 필드 이름 처리
    }
  }

  /// 모든 입력 필드를 초기화
  void clearInput() {
    _inputFields.updateAll((key, value) => ''); // 모든 필드 값을 빈 문자열로 설정
    notifyListeners(); // 상태 변경 알림
  }

  /// 특정 필드의 값이 유효한지 확인
  /// @param field - 필드 이름
  /// @param value - 검증할 값
  /// @return bool - 유효성 결과
  bool isValidField(String field, String value) {
    switch (field) {
      case front_3:
      case back_4:
        return RegExp(r'^\d{0,3}$').hasMatch(value); // 최대 3자리 숫자 검증
      case middle_1:
        return RegExp(r'^\d{0,1}$').hasMatch(value); // 최대 1자리 숫자 검증
      default:
        return false; // 유효하지 않은 필드 이름
    }
  }

  /// 검증 후 필드 값을 업데이트
  /// @param field - 필드 이름
  /// @param value - 업데이트할 값
  void updateFieldWithValidation(String field, String value) {
    if (!_inputFields.containsKey(field)) {
      debugPrint('Error: Invalid field name: $field'); // 디버그 로그 출력
      throw ArgumentError('Invalid field name: $field'); // 필드 이름 검증 실패
    }

    if (!isValidField(field, value)) {
      debugPrint('Error: Invalid value for field $field: $value'); // 디버그 로그 출력
      throw ArgumentError('Invalid value for field $field: $value'); // 값 검증 실패
    }

    updateField(field, value); // 필드 업데이트
  }
}
