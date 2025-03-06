import 'package:flutter/material.dart';

/// 지역 상태 관리 클래스
class AreaState with ChangeNotifier {
  String _currentArea = ''; // 현재 선택된 지역
  final Set<String> _availableAreas = {'dev', 'test', 'release', '본사', '가로수길'};

  String get currentArea => _currentArea;
  List<String> get availableAreas => _availableAreas.toList();

  /// ✅ 상태 변경 알림 (UI 빌드 중 호출 방지)
  void _notifyStateChange() {
    Future.microtask(() => notifyListeners()); // 🔥 UI 빌드 이후에 실행
  }

  /// ✅ 지역 상태 초기화 또는 동기화
  void initializeOrSyncArea(String area) {
    if (_currentArea != area) {
      updateArea(area, isSyncing: true);
    }
  }

  /// ✅ 지역 업데이트
  void updateArea(String newArea, {bool isSyncing = false}) {
    if (_availableAreas.contains(newArea) && _currentArea != newArea) {
      _currentArea = newArea;
      _notifyStateChange();
      debugPrint(isSyncing ? '🔄 지역 동기화: $_currentArea' : '✅ 지역 업데이트: $_currentArea');
    } else if (!_availableAreas.contains(newArea)) {
      debugPrint('⚠️ 잘못된 지역 입력: $newArea');
    }
  }
}
