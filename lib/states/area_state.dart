import 'package:flutter/material.dart';

/// **지역 상태 관리 클래스**
/// - 사용 가능한 지역과 현재 선택된 지역을 관리
/// - 지역 변경 시 상태 변화를 알림
class AreaState with ChangeNotifier {
  // 현재 선택된 지역, 기본값은 'Area A'
  String _currentArea = 'Area A';

  // 사용 가능한 지역 목록
  final List<String> _availableAreas = ['Area A', 'Area B', 'Area C'];

  /// **현재 선택된 지역 반환**
  /// - 외부에서 현재 선택된 지역을 가져올 때 사용
  String get currentArea => _currentArea;

  /// **사용 가능한 지역 목록 반환**
  /// - 외부에서 사용 가능한 지역 목록을 가져올 때 사용
  List<String> get availableAreas => _availableAreas;

  /// **지역 변경 메서드**
  /// - [newArea]: 새로 선택된 지역
  /// - 현재 선택된 지역과 다르면 상태를 업데이트하고 알림
  void updateArea(String newArea) {
    if (_currentArea != newArea) {
      _currentArea = newArea; // 현재 지역 업데이트
      notifyListeners(); // 상태 변경 알림
    }
  }
}