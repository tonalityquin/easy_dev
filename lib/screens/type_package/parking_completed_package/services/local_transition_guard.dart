import 'package:flutter/foundation.dart';

/// 내가 방금 'parking_completed'로 전이시킨 (plateNumber, area)을
/// 짧은 시간(window) 동안 기억해두어 스트림 재유입 시 중복 로깅을 방지.
class LocalTransitionGuard {
  LocalTransitionGuard._();
  static final LocalTransitionGuard instance = LocalTransitionGuard._();

  final Map<String, DateTime> _recent = <String, DateTime>{};

  /// 중복 방지 시간창 (필요하면 조정)
  @visibleForTesting
  final Duration window = const Duration(seconds: 5);

  String _key(String plateNumber, String area) => '$plateNumber|$area';

  /// 사용자가 방금 parking_completed로 만든 건을 마킹
  void markUserParkingCompleted({
    required String plateNumber,
    required String area,
  }) {
    _recent[_key(plateNumber, area)] = DateTime.now();
  }

  /// 스트림 로깅 전에 호출: 최근 내 작업이면 true
  bool hasRecentUserMark({
    required String plateNumber,
    required String area,
  }) {
    final t = _recent[_key(plateNumber, area)];
    if (t == null) return false;
    return DateTime.now().difference(t) < window;
  }
}
