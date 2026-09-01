import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dashboard/applications/common/endtime_reminder_service.dart';
import '../../features/dashboard/widgets/utils/productivity_tools.dart';
import 'foreground_entrypoints.dart';
import 'local_notifications.dart';
import 'work_schedule_prefs.dart';

@immutable
class StartupReport {
  const StartupReport({
    required this.notificationsReady,
    required this.reminderReady,
    required this.chillStoreReady,
    required this.foregroundServiceReady,
  });

  final bool notificationsReady;
  final bool reminderReady;
  final bool chillStoreReady;
  final bool foregroundServiceReady;

  int get readyCount => <bool>[
        notificationsReady,
        reminderReady,
        chillStoreReady,
        foregroundServiceReady,
      ].where((value) => value).length;

  bool get allReady => readyCount == 4;
}

class StartupTasks {
  static bool _ran = false;
  static StartupReport? _lastReport;
  static final List<String> _debugLines = <String>[];

  static StartupReport? get lastReport => _lastReport;
  static List<String> get debugLines => List<String>.unmodifiable(_debugLines);

  static void _log(String message) {
    debugPrint(message);
    _debugLines.add(message);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
  }

  static Future<StartupReport> runAfterPermissions() async {
    if (_ran && _lastReport != null) return _lastReport!;
    _ran = true;

    var notificationsReady = false;
    var reminderReady = false;
    var chillStoreReady = false;
    var foregroundServiceReady = false;

    try {
      await LocalNotifications.ensureInitialized();
      notificationsReady = true;
      _log('[STARTUP] LocalNotifications ready');
    } catch (e, st) {
      _log('[STARTUP] LocalNotifications error: $e');
      _log('[STARTUP] LocalNotifications stackTrace: $st');
    }

    try {
      EndTimeReminderService.instance.attachPlugin(LocalNotifications.plugin);
      await _applyEndTimeReminderFromPrefs();
      reminderReady = true;
      _log('[STARTUP] EndTimeReminderService ready');
    } catch (e, st) {
      _log('[STARTUP] EndTimeReminderService error: $e');
      _log('[STARTUP] EndTimeReminderService stackTrace: $st');
    }

    try {
      await ChillStore.instance.init();
      chillStoreReady = true;
      _log('[STARTUP] ChillStore ready');
    } catch (e, st) {
      _log('[STARTUP] ChillStore error: $e');
      _log('[STARTUP] ChillStore stackTrace: $st');
    }

    try {
      foregroundServiceReady = await ensureForegroundServiceRunning();
    } catch (e, st) {
      _log('[STARTUP] Foreground service error: $e');
      _log('[STARTUP] Foreground service stackTrace: $st');
    }

    final report = StartupReport(
      notificationsReady: notificationsReady,
      reminderReady: reminderReady,
      chillStoreReady: chillStoreReady,
      foregroundServiceReady: foregroundServiceReady,
    );
    _lastReport = report;
    _log(
      '[STARTUP] report ready=${report.readyCount}/4 allReady=${report.allReady}',
    );
    return report;
  }

  static Future<bool> ensureForegroundServiceRunning() async {
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        _log('[STARTUP] Foreground service already running');
        return true;
      }
      await FlutterForegroundTask.startService(
        notificationTitle: 'ParkinWorkin',
        notificationText: '포그라운드에서 대기 중',
        callback: myForegroundCallback,
      );
      _log('[STARTUP] Foreground service start request completed');
      for (var attempt = 1; attempt <= 4; attempt++) {
        final started = await FlutterForegroundTask.isRunningService;
        _log(
          '[STARTUP] Foreground service verify attempt=$attempt running=$started',
        );
        if (started) {
          _log('[STARTUP] Foreground service ensure result=true');
          return true;
        }
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
      _log('[STARTUP] Foreground service ensure result=false');
      return false;
    } catch (e, st) {
      _log('[STARTUP] Foreground service ensure error: $e');
      _log('[STARTUP] Foreground service ensure stackTrace: $st');
      return false;
    }
  }

  static Future<void> _applyEndTimeReminderFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
  }
}
