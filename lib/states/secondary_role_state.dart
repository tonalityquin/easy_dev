import 'package:flutter/material.dart';
import 'secondary_info.dart'; // Import for fieldModePages and officeModePages

/// **관리 클래스**
class SecondaryRoleState with ChangeNotifier {
  // 현재 선택된 모드, 기본값은 'Office Mode'
  String _currentStatus = 'Office Mode';

  // 사용 가능한 모드 목록
  final List<String> _availableStatus = ['Field Mode', 'Office Mode'];

  // 현재 선택된 지역
  String? _currentArea;

  /// **현재 선택된 모드 반환**
  String get currentStatus => _currentStatus;

  /// **사용 가능한 모드 목록 반환**
  List<String> get availableStatus => _availableStatus;

  /// **현재 모드에 따른 페이지 목록 반환**
  List<SecondaryInfo> get pages {
    return _currentStatus == 'Field Mode' ? fieldModePages : officeModePages;
  }

  /// **현재 선택된 지역 반환**
  String? get currentArea => _currentArea;

  /// **모드 변경 메서드**
  void updateManage(String newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus; // 현재 모드 업데이트
      notifyListeners(); // 상태 변경 알림
    }
  }

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
