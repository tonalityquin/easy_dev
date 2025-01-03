import 'package:flutter/material.dart';

class UIState with ChangeNotifier {
  bool _showKeypad = true;
  bool _isLoading = false;
  String? _activeController; // 현재 활성화된 입력 필드를 나타내는 변수

  // 키패드 표시 여부
  bool get showKeypad => _showKeypad;

  // 로딩 상태
  bool get isLoading => _isLoading;

  // 활성화된 컨트롤러 이름 반환
  String? get activeController => _activeController;

  // 키패드 표시 상태 변경
  void toggleKeypad(bool value) {
    _showKeypad = value;
    notifyListeners();
  }

  // 로딩 상태 변경
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // 활성화된 컨트롤러 이름 설정
  void setActiveController(String controller) {
    _activeController = controller;
    notifyListeners();
  }

  // 모든 상태 초기화
  void resetState() {
    _showKeypad = true;
    _isLoading = false;
    _activeController = null;
    notifyListeners();
  }
}
