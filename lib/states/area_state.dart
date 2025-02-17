import 'package:flutter/material.dart';

/// 지역 상태 관리 클래스
/// - 현재 선택된 지역 및 사용 가능한 지역 목록 관리
class AreaState with ChangeNotifier {
  String _currentArea = ''; // 현재 선택된 지역

  // 사용 가능한 지역 목록
  final List<String> _availableAreas = ['dev', 'test', 'release', '본사', '가로수길'];

  // 현재 지역 반환
  String get currentArea => _currentArea;

  // 사용 가능한 지역 목록 반환
  List<String> get availableAreas => List.unmodifiable(_availableAreas);

  /// 상태 변경 알림
  /// - 중복 제거를 위해 상태 변경 로직을 메서드로 추출
  void _notifyStateChange() {
    Future.delayed(Duration.zero, notifyListeners);
  }

  /// 지역 상태 초기화 또는 사용자 상태와 동기화
  /// - 유효한 지역으로 초기화하거나 동기화
  void initializeOrSyncArea(String area) {
    if (_currentArea != area) {
      if (_availableAreas.contains(area) && area.isNotEmpty) {
        _currentArea = area;
      } else {
        _currentArea = _availableAreas.first; // 기본값 설정
      }
      _notifyStateChange(); // 중복 제거
      debugPrint('지역 동기화/초기화: 선택된 지역=$_currentArea');
    }
  }

  /// 지역 업데이트
  /// - 새로운 지역으로 상태를 업데이트
  void updateArea(String newArea) {
    if (_availableAreas.contains(newArea) && _currentArea != newArea) {
      _currentArea = newArea;
      _notifyStateChange(); // 중복 제거
      debugPrint('지역 업데이트: 선택된 지역=$_currentArea');
    } else if (!_availableAreas.contains(newArea)) {
      debugPrint('잘못된 지역: $newArea');
    }
  }
}
