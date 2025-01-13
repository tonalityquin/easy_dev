import 'package:flutter/material.dart';

/// **노무 관리 클래스**
class ManagementState with ChangeNotifier {
  // 현재 선택된 지역, 기본값은 'Area A'
  String _currentArea = 'user';

  // 사용 가능한 지역 목록
  final List<String> _availableAreas = ['user', 'location'];

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
