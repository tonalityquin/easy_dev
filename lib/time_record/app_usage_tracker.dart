// lib/time_record/app_usage_tracker.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'work_time_repository.dart';

String _ts() => DateTime.now().toIso8601String();

/// 앱의 라이프사이클(AppLifecycleState)을 받아서
/// - 현재 세션(foregroundTime/backgroundTime) 누적
/// - WorkTimeRepository 를 통해 날짜별 DB에 적립
class AppUsageTracker {
  AppUsageTracker._internal();

  static final AppUsageTracker instance = AppUsageTracker._internal();

  DateTime? _sessionStart;
  DateTime? _lastStateChangedAt;
  AppLifecycleState? _lastState;

  /// 현재 세션 내 포그라운드/백그라운드 누적 시간
  Duration foregroundTime = Duration.zero;
  Duration backgroundTime = Duration.zero;

  void _ensureSessionStarted() {
    final now = DateTime.now();
    _sessionStart ??= now;
    _lastStateChangedAt ??= now;
  }

  /// AppLifecycleState 변경 시 호출
  ///
  /// - 이전 상태(_lastState) 기준으로 [lastStateChangedAt, now) 구간을
  ///   foreground / background 중 하나로 판단해서 누적 + DB 적립
  void onStateChange(AppLifecycleState newState) {
    final now = DateTime.now();
    _ensureSessionStarted();

    if (_lastState != null && _lastStateChangedAt != null) {
      final start = _lastStateChangedAt!;
      final end = now;
      final delta = end.difference(start);
      if (delta.inSeconds > 0) {
        final wasForeground = _lastState == AppLifecycleState.resumed;

        if (wasForeground) {
          foregroundTime += delta;
        } else {
          backgroundTime += delta;
        }

        // 비동기 DB 기록 (await 없이, 오류는 내부 catch)
        WorkTimeRepository.instance
            .recordInterval(
          start: start,
          end: end,
          isForeground: wasForeground,
        )
            .catchError((e, st) {
          debugPrint('[USAGE][$_ts()] recordInterval error: $e');
          debugPrint(st.toString());
        });

        debugPrint(
          '[USAGE][$_ts()] '
              'interval ${wasForeground ? 'FG' : 'BG'} '
              '${delta.inSeconds}s '
              'fg=${foregroundTime.inSeconds}s '
              'bg=${backgroundTime.inSeconds}s',
        );
      }
    }

    _lastState = newState;
    _lastStateChangedAt = now;
  }

  Duration get totalElapsed {
    if (_sessionStart == null) return Duration.zero;
    return DateTime.now().difference(_sessionStart!);
  }

  /// 세션 통계만 리셋(DB 기록은 유지)
  void resetSession() {
    _sessionStart = null;
    _lastState = null;
    _lastStateChangedAt = null;
    foregroundTime = Duration.zero;
    backgroundTime = Duration.zero;
    debugPrint('[USAGE][$_ts()] resetSession');
  }
}
