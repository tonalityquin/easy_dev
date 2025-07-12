import 'package:flutter/material.dart';

/// 🔹 모드 상태 정의
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

/// 🔹 모드 상태의 label (한글명) 정의
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

  /// 🔹 라벨로부터 ModeStatus enum 값 가져오기
  static ModeStatus? fromLabel(String label) {
    return ModeStatus.values.firstWhere(
          (e) => e.label == label,
      orElse: () => ModeStatus.managerField,
    );
  }
}

/// 🔹 모드 상태 관리 클래스
class SecondaryMode with ChangeNotifier {
  ModeStatus _currentStatus = ModeStatus.managerField;
  String? _currentArea;

  ModeStatus get currentStatus => _currentStatus;
  String? get currentArea => _currentArea;

  List<String> get availableStatus => ModeStatus.values.map((e) => e.label).toList();

  /// ✅ [기존 방식] 문자열 기반 모드 변경 (내부 또는 바텀시트에서 사용)
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

  /// ✅ [신규 추가] enum 기반 모드 변경 (외부에서 직접 사용하기 위함)
  void changeStatus(ModeStatus newStatus) {
    if (_currentStatus == newStatus) return;
    _currentStatus = newStatus;
    notifyListeners();
    debugPrint('✅ 모드 변경됨: ${_currentStatus.label}');
  }
}
