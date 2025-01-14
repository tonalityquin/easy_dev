import 'package:flutter/material.dart';
import 'secondary_info.dart'; // Import for fieldModePages and officeModePages

/// **관리 클래스**
class SecondaryRoleState with ChangeNotifier {
  // 현재 선택된 모드, 기본값은 'Field Mode'
  String _currentStatus = 'Office Mode';

  // 사용 가능한 모드 목록
  final List<String> _availableStatus = ['Field Mode', 'Office Mode'];

  /// **현재 선택된 모드 반환**
  /// - 외부에서 현재 선택된 모드를 가져올 때 사용
  String get currentStatus => _currentStatus;

  /// **사용 가능한 모드 목록 반환**
  /// - 외부에서 사용 가능한 모드 목록을 가져올 때 사용
  List<String> get availableStatus => _availableStatus;

  /// **현재 모드에 따른 페이지 목록 반환**
  List<SecondaryInfo> get pages {
    return _currentStatus == 'Field Mode' ? fieldModePages : officeModePages;
  }

  /// **모드 변경 메서드**
  /// - [newStatus]: 새로 선택된 모드
  /// - 현재 선택된 모드와 다르면 상태를 업데이트하고 알림
  void updateManage(String newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus; // 현재 모드 업데이트
      notifyListeners(); // 상태 변경 알림
    }
  }
}
