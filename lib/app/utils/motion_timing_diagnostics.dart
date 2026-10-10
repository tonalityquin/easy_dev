import 'dart:convert';

import 'package:flutter/foundation.dart';

class AppFlowPacing {
  const AppFlowPacing._();

  static const Duration launcherPermissionAdvance = Duration(milliseconds: 420);
  static const Duration launcherPermissionResumeAdvance =
      Duration(milliseconds: 280);
  static const Duration terminalSettingCommand = Duration(milliseconds: 105);
  static const Duration terminalEmailCommand = Duration(milliseconds: 105);
  static const Duration terminalProtectedCommand = Duration(milliseconds: 180);
  static const Duration modeTerminalExit = Duration(milliseconds: 160);
  static const Duration commuteEndTimeResult = Duration(milliseconds: 650);
  static const Duration commuteClockInSuccess = Duration(milliseconds: 420);
  static const Duration launcherInitialPresentation = Duration(milliseconds: 520);
}

class MotionTimingDiagnostics {
  const MotionTimingDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[MOTION_TIMING] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static void record(
    String event, {
    required String scope,
    bool? reduceMotion,
    Duration? duration,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[MOTION_TIMING]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'scope=$scope',
      'event=$event',
      if (reduceMotion != null) 'reduceMotion=$reduceMotion',
      if (duration != null) 'durationMs=${duration.inMilliseconds}',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${entry.value}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 320) {
      _lines.removeRange(0, _lines.length - 320);
    }
  }

  static Future<void> waitForFlow(
    String event,
    Duration duration, {
    required String scope,
    required bool reduceMotion,
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    record(
      '${event}_start',
      scope: scope,
      reduceMotion: reduceMotion,
      duration: duration,
      meta: meta,
    );
    if (duration.inMicroseconds > 0) {
      await Future<void>.delayed(duration);
    }
    record(
      '${event}_complete',
      scope: scope,
      reduceMotion: reduceMotion,
      duration: duration,
      meta: meta,
    );
  }
}
