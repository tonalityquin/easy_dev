import 'package:flutter/material.dart';

/// **관리 클래스**
class ManagementState with ChangeNotifier {
  // 현재 선택된 지역, 기본값은 'working'
  String _currentStatus = 'Field Mode';

  // 사용 가능한 지역 목록
  final List<String> _availableStatus = ['Field Mode', 'Office Mode'];

  /// **현재 선택된 지역 반환**
  /// - 외부에서 현재 선택된 지역을 가져올 때 사용
  String get currentStatus => _currentStatus;

  /// **사용 가능한 지역 목록 반환**
  /// - 외부에서 사용 가능한 지역 목록을 가져올 때 사용
  List<String> get availableStatus => _availableStatus;

  /// **지역 변경 메서드**
  /// - [newStatus]: 새로 선택된 지역
  /// - 현재 선택된 지역과 다르면 상태를 업데이트하고 알림
  void updateManage(String newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus; // 현재 지역 업데이트
      notifyListeners(); // 상태 변경 알림
    }
  }
}
