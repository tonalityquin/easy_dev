import 'package:flutter/material.dart';

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
        return '보조 페이지';
      case ModeStatus.office:
        return '관리 페이지';
      case ModeStatus.document:
        return '이스터 에그';
      case ModeStatus.dev:
        return '개발자 페이지';
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
}
