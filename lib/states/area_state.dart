import 'package:flutter/material.dart';

class AreaState with ChangeNotifier {
  // 현재 선택된 지역
  String _currentArea = ''; // 기본값 제거

  // 사용 가능한 지역 목록
  final List<String> _availableAreas = ['Seoul', 'Incheon', 'YangJoo'];

  // 현재 지역 반환
  String get currentArea => _currentArea;

  // 사용 가능한 지역 목록 반환
  List<String> get availableAreas => List.unmodifiable(_availableAreas);

  // 지역 상태 초기화 (외부 상태와 동기화)
  void initializeArea(String area) {
    // 현재 지역이 변경되지 않았으면 초기화하지 않음
    if (_currentArea != area) {
      if (_availableAreas.contains(area) && area.isNotEmpty) {
        _currentArea = area;
      } else {
        _currentArea = _availableAreas.first; // 기본값 설정
      }

      // notifyListeners() 호출을 Future.delayed로 지연시켜, 위젯 빌드 후에 호출
      Future.delayed(Duration.zero, () {
        notifyListeners();
      });

      debugPrint('AreaState initialized: currentArea=$_currentArea');
    }
  }

  // UserState와 동기화
  void syncWithUserState(String userArea) {
    initializeArea(userArea);
  }

  // 지역 업데이트
  void updateArea(String newArea) {
    if (_availableAreas.contains(newArea) && _currentArea != newArea) {
      _currentArea = newArea;

      // notifyListeners() 호출을 Future.delayed로 지연시켜, 위젯 빌드 후에 호출
      Future.delayed(Duration.zero, () {
        notifyListeners(); // 상태 변경 알림
      });

      debugPrint('AreaState updated: currentArea=$_currentArea');
    } else if (!_availableAreas.contains(newArea)) {
      debugPrint('잘못된 지역: $newArea');
    }
  }
}
