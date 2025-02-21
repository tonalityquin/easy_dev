import 'package:flutter/material.dart';
import 'secondary_info.dart'; // fieldModePages 및 officeModePages 정의를 위한 import

/// SecondaryAccessState
/// - 사용자 모드(Office/Field/Statistics)와 지역 상태 관리
/// - 모드 및 지역 변경 시 상태 알림
class SecondaryAccessState with ChangeNotifier {
  String _currentStatus = 'Field Mode'; // 현재 모드 (기본값: Field Mode)
  final List<String> _availableStatus = ['Field Mode', 'Office Mode', 'Statistics Mode']; // 선택 가능한 모드 목록
  String? _currentArea; // 현재 선택된 지역

  // 🔹 (1) 현재 상태 반환 (Getter)
  String get currentStatus => _currentStatus;
  String? get currentArea => _currentArea;
  List<String> get availableStatus => _availableStatus;

  /// 🔹 (2) 현재 모드에 따른 페이지 목록 반환
  /// - Field Mode: `fieldModePages`
  /// - Office Mode: `officeModePages`
  /// - Statistics Mode: `statisticsPages`
  List<SecondaryInfo> get pages {
    if (_currentStatus == 'Field Mode') {
      return fieldModePages;
    } else if (_currentStatus == 'Office Mode') {
      return officeModePages;
    } else {
      return statisticsPages; // ✅ Statistics Mode 추가
    }
  }

  /// 🔹 (3) 모드 업데이트
  /// - [newStatus]: 새로운 모드
  /// - 상태가 변경되면 알림
  void updateManage(String newStatus) {
    if (!_availableStatus.contains(newStatus) || _currentStatus == newStatus) {
      return; // 🚀 변경되지 않은 경우 `notifyListeners()` 호출 안 함
    }
    _currentStatus = newStatus;
    notifyListeners();
  }

  /// 🔹 (4) 지역 업데이트
  /// - [newArea]: 새로운 지역
  /// - 상태가 변경되면 알림
  void updateArea(String? newArea) {
    if (newArea == null || newArea.trim().isEmpty || _currentArea == newArea) {
      return; // 🚀 변경되지 않은 경우 `notifyListeners()` 호출 안 함
    }
    _currentArea = newArea;
    notifyListeners();
  }
}
