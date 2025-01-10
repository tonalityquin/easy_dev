import 'package:flutter/material.dart';

/// 지역 상태 관리
class AreaState with ChangeNotifier {
  String _currentArea = 'Area A'; // 기본 지역
  final List<String> _availableAreas = ['Area A', 'Area B', 'Area C']; // 사용 가능한 지역 목록

  String get currentArea => _currentArea;
  List<String> get availableAreas => _availableAreas;

  void updateArea(String newArea) {
    if (_currentArea != newArea) {
      _currentArea = newArea;
      notifyListeners(); // 상태 변경 알림
    }
  }
}
