import 'package:flutter/material.dart';
import 'secondary_info.dart';

enum ModeStatus {
  field,
  office,
  document,
  dev,
}

extension ModeStatusExtension on ModeStatus {
  String get label {
    switch (this) {
      case ModeStatus.field:
        return 'Field Mode';
      case ModeStatus.office:
        return 'Office Mode';
      case ModeStatus.document:
        return 'Document Mode';
      case ModeStatus.dev:
        return 'Dev Mode';
    }
  }

  static ModeStatus? fromLabel(String label) {
    return ModeStatus.values.firstWhere(
      (e) => e.label == label,
      orElse: () => ModeStatus.field,
    );
  }
}

class SecondaryMode with ChangeNotifier {
  ModeStatus _currentStatus = ModeStatus.field;
  String? _currentArea;

  ModeStatus get currentStatus => _currentStatus;

  String? get currentArea => _currentArea;

  List<String> get availableStatus => ModeStatus.values.map((e) => e.label).toList();

  List<SecondaryInfo> get pages {
    switch (_currentStatus) {
      case ModeStatus.office:
        return officeModePages;
      case ModeStatus.document:
        return documentPages;
      case ModeStatus.field:
        return fieldModePages;
      case ModeStatus.dev:
        return devPages;
    }
  }

  void updateManage(String newStatus) {
    final selectedStatus = ModeStatusExtension.fromLabel(newStatus);
    if (selectedStatus == null) {
      debugPrint('🚨 잘못된 모드 선택: $newStatus');
      return;
    }
    if (_currentStatus == selectedStatus) return;
    _currentStatus = selectedStatus;
    notifyListeners();
    debugPrint('✅ 모드 변경됨: ${_currentStatus.label}');
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
