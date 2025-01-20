import 'package:flutter/material.dart';

/// 지역 상태 관리 클래스
/// - 현재 선택된 지역 및 사용 가능한 지역 목록 관리
class AreaState with ChangeNotifier {
  String _currentArea = ''; // 현재 선택된 지역

  // 사용 가능한 지역 목록
  final List<String> _availableAreas = ['Seoul', 'Incheon', 'YangJoo'];

  // 현재 지역 반환
  String get currentArea => _currentArea;

  // 사용 가능한 지역 목록 반환
  List<String> get availableAreas => List.unmodifiable(_availableAreas);

  /// 지역 상태 초기화
  /// - 외부 상태와 동기화하며, 유효한 지역으로 초기화
  void initializeArea(String area) {
    if (_currentArea != area) {
      if (_availableAreas.contains(area) && area.isNotEmpty) {
        _currentArea = area;
      } else {
        _currentArea = _availableAreas.first; // 기본값 설정
      }

      // 상태 변경 알림을 위젯 빌드 이후에 호출
      Future.delayed(Duration.zero, () {
        notifyListeners();
      });

      debugPrint('AreaState initialized: currentArea=$_currentArea');
    }
  }

  /// 사용자 상태와 지역 동기화
  /// - `UserState`의 지역 정보와 일치시킴
  void syncWithUserState(String userArea) {
    initializeArea(userArea);
  }

  /// 지역 업데이트
  /// - 새로운 지역으로 상태를 업데이트
  void updateArea(String newArea) {
    if (_availableAreas.contains(newArea) && _currentArea != newArea) {
      _currentArea = newArea;

      // 상태 변경 알림을 위젯 빌드 이후에 호출
      Future.delayed(Duration.zero, () {
        notifyListeners();
      });

      debugPrint('AreaState updated: currentArea=$_currentArea');
    } else if (!_availableAreas.contains(newArea)) {
      debugPrint('잘못된 지역: $newArea');
    }
  }
}
