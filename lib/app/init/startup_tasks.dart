import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dashboard/applications/common/endtime_reminder_service.dart';
import '../../features/dashboard/widgets/utils/productivity_tools.dart';
import 'local_notifications.dart';
import 'work_schedule_prefs.dart';
import 'work_status_notification.dart';

@immutable
class StartupReport {
  const StartupReport({
    required this.notificationsReady,
    required this.reminderReady,
    required this.chillStoreReady,
    required this.foregroundServiceReady,
    required this.foregroundServiceRunning,
  });

  final bool notificationsReady;
  final bool reminderReady;
  final bool chillStoreReady;
  final bool foregroundServiceReady;
  final bool foregroundServiceRunning;

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
    var foregroundServiceRunning = false;

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
      foregroundServiceReady = await WorkStatusNotificationController.refresh(
        source: 'startup_work_state',
      );
      foregroundServiceRunning =
          WorkStatusNotificationController.status.value.serviceRunning;
      _log(
        '[STARTUP] Foreground lifecycle ready=$foregroundServiceReady running=$foregroundServiceRunning working=${WorkStatusNotificationController.status.value.isWorking}',
      );
    } catch (e, st) {
      _log('[STARTUP] Foreground lifecycle error: $e');
      _log('[STARTUP] Foreground lifecycle stackTrace: $st');
    }

    final report = StartupReport(
      notificationsReady: notificationsReady,
      reminderReady: reminderReady,
      chillStoreReady: chillStoreReady,
      foregroundServiceReady: foregroundServiceReady,
      foregroundServiceRunning: foregroundServiceRunning,
    );
    _lastReport = report;
    _log(
      '[STARTUP] report ready=${report.readyCount}/4 allReady=${report.allReady}',
    );
    return report;
  }

  static Future<ForegroundServiceEnsureResult>
      ensureForegroundServiceState({
    String source = 'startup_tasks',
  }) async {
    final result = await WorkStatusNotificationController.ensureServiceState(
      source: source,
    );
    _log(
      '[STARTUP] Foreground service ensure running=${result.running} startedNow=${result.startedNow} source=${result.source}',
    );
    return result;
  }

  static Future<bool> ensureForegroundServiceRunning() async {
    final result = await ensureForegroundServiceState();
    return result.running;
  }

  static Future<void> _applyEndTimeReminderFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
  }
}
