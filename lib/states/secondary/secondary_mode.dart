import 'package:flutter/material.dart';

enum ModeStatus {
  admin,
  lowField,
  middleField,
  highField,
  managerField,
  lowMiddleManage,
  highManage,
  dev,
}

extension ModeStatusExtension on ModeStatus {
  String get label {
    switch (this) {
      case ModeStatus.admin:
        return '개발용 페이지';
      case ModeStatus.lowField:
        return '사용자 페이지';
      case ModeStatus.middleField:
        return '팀장 페이지';
      case ModeStatus.highField:
        return '총괄 팀장 페이지';
      case ModeStatus.managerField:
        return '관리자 필드 페이지';
      case ModeStatus.lowMiddleManage:
        return '관리자 관리 페이지';
      case ModeStatus.highManage:
        return '상급 관리자 관리 페이지';
      case ModeStatus.dev:
        return '개발자 페이지';
    }
  }

  static ModeStatus? fromLabel(String label) {
    return ModeStatus.values.firstWhere(
          (e) => e.label == label,
      orElse: () => ModeStatus.managerField,
    );
  }
}

class SecondaryMode with ChangeNotifier {
  ModeStatus _currentStatus = ModeStatus.managerField;
  String? _currentArea;

  ModeStatus get currentStatus => _currentStatus;
  String? get currentArea => _currentArea;

  List<String> get availableStatus => ModeStatus.values.map((e) => e.label).toList();

  void changeStatus(ModeStatus newStatus) {
    if (_currentStatus == newStatus) return;
    _currentStatus = newStatus;
    notifyListeners();
    debugPrint('✅ 모드 변경됨: ${_currentStatus.label}');
  }
}
