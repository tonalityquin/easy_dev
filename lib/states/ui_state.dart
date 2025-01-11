import 'package:flutter/material.dart';

/// **UIState 클래스**
/// - 사용자 인터페이스(UI) 상태를 관리하는 클래스
/// - 키패드 표시 여부, 로딩 상태, 입력 필드 상태 등을 포함
class UIState with ChangeNotifier {
  // 키패드 표시 여부
  bool _showKeypad = true;

  // 로딩 상태
  bool _isLoading = false;

  // 입력 필드 상태를 저장하는 맵
  final Map<String, InputFieldState> _inputFields = {};

  /// **키패드 표시 여부**
  /// - 키패드가 표시 중인지 확인
  bool get showKeypad => _showKeypad;

  /// **로딩 상태**
  /// - 현재 로딩 중인지 확인
  bool get isLoading => _isLoading;

  /// **특정 입력 필드 상태 가져오기**
  /// - [fieldName]: 상태를 가져올 필드 이름
  /// - 반환값: `InputFieldState` 또는 `null` (필드가 없는 경우)
  InputFieldState? getFieldState(String fieldName) => _inputFields[fieldName];

  /// **키패드 표시 상태 토글**
  /// - [value]: 새로운 키패드 표시 상태 (true 또는 false)
  void toggleKeypad(bool value) {
    if (_showKeypad != value) {
      _showKeypad = value;
      notifyListeners(); // 상태 변경 알림
    }
  }

  /// **로딩 상태 설정**
  /// - [value]: 새로운 로딩 상태 (true 또는 false)
  void setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners(); // 상태 변경 알림
    }
  }

  /// **입력 필드 상태 설정**
  /// - [fieldName]: 상태를 설정할 필드 이름
  /// - [state]: 새로 설정할 입력 필드 상태
  void setFieldState(String fieldName, InputFieldState state) {
    _inputFields[fieldName] = state; // 필드 상태 업데이트
    notifyListeners(); // 상태 변경 알림
  }

  /// **특정 입력 필드 활성화**
  /// - [fieldName]: 활성화할 필드 이름
  /// - 해당 필드 외 다른 필드는 비활성화
  void activateField(String fieldName) {
    _inputFields.forEach((key, fieldState) {
      fieldState.isActive = (key == fieldName); // 주어진 필드만 활성화
    });
    notifyListeners(); // 상태 변경 알림
  }

  /// **UI 상태 초기화**
  /// - 키패드 표시, 로딩 상태, 입력 필드 상태를 초기화
  void resetState() {
    _showKeypad = true; // 키패드 표시 초기화
    _isLoading = false; // 로딩 상태 초기화
    _inputFields.clear(); // 입력 필드 상태 초기화
    notifyListeners(); // 상태 변경 알림
  }
}

/// **InputFieldState 클래스**
/// - 개별 입력 필드의 상태를 관리하는 클래스
class InputFieldState {
  bool isActive; // 현재 필드가 활성화 상태인지 여부
  bool isValid; // 현재 필드 값이 유효한지 여부
  String value; // 현재 필드에 입력된 값

  /// **InputFieldState 생성자**
  /// - [isActive]: 필드 활성 상태 (기본값: false)
  /// - [isValid]: 필드 유효 상태 (기본값: true)
  /// - [value]: 필드 값 (기본값: 빈 문자열)
  InputFieldState({
    this.isActive = false,
    this.isValid = true,
    this.value = '',
  });
}
