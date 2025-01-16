import 'package:flutter/material.dart';

class AreaState with ChangeNotifier {
  // 현재 선택된 지역 (기본값은 _availableAreas의 첫 번째 값)
  String _currentArea;

  // 사용 가능한 지역 목록
  final List<String> _availableAreas = ['Seoul', 'Incheon', 'YangJoo'];

  // 생성자에서 currentArea 기본값 초기화
  AreaState() : _currentArea = 'Seoul'; // 기본값을 'Seoul'로 설정

  String get currentArea => _currentArea;

  List<String> get availableAreas => List.unmodifiable(_availableAreas);

  void updateArea(String newArea) {
    // 새로운 지역이 유효하고 현재 지역과 다를 경우 업데이트
    if (_availableAreas.contains(newArea) && _currentArea != newArea) {
      _currentArea = newArea;
      notifyListeners(); // 상태 변경 알림
    } else if (!_availableAreas.contains(newArea)) {
      debugPrint('잘못된 지역: $newArea');
    }
  }
}
