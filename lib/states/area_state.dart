import 'package:flutter/material.dart';

class AreaState with ChangeNotifier {
  String _currentArea = '';
  final Set<String> _availableAreas = {'dev', 'test', 'release', '본사', '가로수길'};

  String get currentArea => _currentArea;

  List<String> get availableAreas => _availableAreas.toList();

  void _notifyStateChange() {
    Future.microtask(() => notifyListeners());
  }

  void initializeOrSyncArea(String area) {
    if (_currentArea != area) {
      updateArea(area, isSyncing: true);
    }
  }

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
