import 'package:flutter/material.dart';
import 'secondary_info.dart';

class SecondaryMode with ChangeNotifier {
  String _currentStatus = 'Field Mode';
  final List<String> _availableStatus = ['Field Mode', 'Office Mode', 'Document Mode'];
  String? _currentArea;

  String get currentStatus => _currentStatus;

  String? get currentArea => _currentArea;

  List<String> get availableStatus => List.unmodifiable(_availableStatus);

  List<SecondaryInfo> get pages {
    switch (_currentStatus) {
      case 'Office Mode':
        return officeModePages;
      case 'Document Mode':
        return documentPages; // ✅ 수정됨: document 모드일 때 해당 페이지 반환
      default:
        return fieldModePages;
    }
  }

  void updateManage(String newStatus) {
    if (!_availableStatus.contains(newStatus)) {
      debugPrint('🚨 잘못된 모드 선택: $newStatus');
      return;
    }
    if (_currentStatus == newStatus) return;
    _currentStatus = newStatus;
    notifyListeners();
    debugPrint('✅ 모드 변경됨: $_currentStatus');
  }

  void updateArea(String? newArea) {
    if (newArea == null || newArea.trim().isEmpty) {
      debugPrint('🚨 잘못된 지역 선택: $newArea');
      return;
    }
    if (_currentArea == newArea) return;
    _currentArea = newArea;
    notifyListeners();
    debugPrint('✅ 지역 변경됨: $_currentArea');
  }
}
