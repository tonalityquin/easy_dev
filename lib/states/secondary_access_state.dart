import 'package:flutter/material.dart';
import 'secondary_info.dart'; // fieldModePages 및 officeModePages 정의를 위한 import

/// **SecondaryAccessState**
/// - 사용자 모드(Office/Field/Statistics) 및 지역 상태 관리
/// - 모드 및 지역 변경 시 상태 알림
class SecondaryAccessState with ChangeNotifier {
  String _currentStatus = 'Field Mode'; // ✅ 현재 모드 (기본값: Field Mode)
  final List<String> _availableStatus = ['Field Mode', 'Office Mode', 'Statistics Mode']; // 선택 가능한 모드 목록
  String? _currentArea; // ✅ 현재 선택된 지역

  /// **(1) 현재 상태 반환 (Getter)**
  String get currentStatus => _currentStatus;
  String? get currentArea => _currentArea;
  List<String> get availableStatus => List.unmodifiable(_availableStatus); // 🚀 불변 리스트 제공

  /// **(2) 현재 모드에 따른 페이지 목록 반환**
  List<SecondaryInfo> get pages {
    switch (_currentStatus) {
      case 'Office Mode':
        return officeModePages;
      case 'Statistics Mode':
        return statisticsPages;
      default:
        return fieldModePages;
    }
  }

  /// **(3) 모드 업데이트**
  /// - [newStatus]: 새로운 모드
  /// - 상태가 변경되면 `notifyListeners()` 호출
  void updateManage(String newStatus) {
    if (!_availableStatus.contains(newStatus)) {
      debugPrint('🚨 잘못된 모드 선택: $newStatus');
      return;
    }
    if (_currentStatus == newStatus) return; // 🚀 변경되지 않은 경우 무시

    _currentStatus = newStatus;
    notifyListeners();
    debugPrint('✅ 모드 변경됨: $_currentStatus');
  }

  /// **(4) 지역 업데이트**
  /// - [newArea]: 새로운 지역
  /// - 상태가 변경되면 `notifyListeners()` 호출
  void updateArea(String? newArea) {
    if (newArea == null || newArea.trim().isEmpty) {
      debugPrint('🚨 잘못된 지역 선택: $newArea');
      return;
    }
    if (_currentArea == newArea) return; // 🚀 변경되지 않은 경우 무시

    _currentArea = newArea;
    notifyListeners();
    debugPrint('✅ 지역 변경됨: $_currentArea');
  }
}
