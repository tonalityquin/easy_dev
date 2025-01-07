import 'package:flutter/material.dart';

class UIState with ChangeNotifier {
  bool _showKeypad = true;
  bool _isLoading = false;
  Map<String, InputFieldState> _inputFields = {}; // 입력 필드 상태를 개별적으로 관리

  // 키패드 표시 여부
  bool get showKeypad => _showKeypad;

  // 로딩 상태
  bool get isLoading => _isLoading;

  // 특정 입력 필드 상태 반환
  InputFieldState? getFieldState(String fieldName) => _inputFields[fieldName];

  // 키패드 표시 상태 변경
  void toggleKeypad(bool value) {
    if (_showKeypad != value) {
      _showKeypad = value;
      notifyListeners();
    }
  }

  // 로딩 상태 변경
  void setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  // 특정 입력 필드 상태 설정
  void setFieldState(String fieldName, InputFieldState state) {
    _inputFields[fieldName] = state;
    notifyListeners();
  }

  // 입력 필드 활성화 상태 설정
  void activateField(String fieldName) {
    _inputFields.forEach((key, fieldState) {
      fieldState.isActive = (key == fieldName);
    });
    notifyListeners();
  }

  // 모든 상태 초기화
  void resetState() {
    _showKeypad = true;
    _isLoading = false;
    _inputFields.clear();
    notifyListeners();
  }
}

// 개별 입력 필드 상태 클래스
class InputFieldState {
  bool isActive; // 활성화 여부
  bool isValid; // 유효성 검사 결과
  String value; // 필드 입력 값

  InputFieldState({
    this.isActive = false,
    this.isValid = true,
    this.value = '',
  });
}
