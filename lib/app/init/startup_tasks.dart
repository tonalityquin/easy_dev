import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/dashboard/applications/common/endtime_reminder_service.dart';
import '../../features/dashboard/widgets/utils/chat_bot_tools.dart';
import 'foreground_entrypoints.dart';
import 'local_notifications.dart';
import 'work_schedule_prefs.dart';

class StartupTasks {
  static bool _ran = false;

  static Future<void> runAfterPermissions() async {
    if (_ran) return;
    _ran = true;

    try {
      await LocalNotifications.ensureInitialized();
    } catch (e) {
      debugPrint('[STARTUP] LocalNotifications.ensureInitialized error: $e');
    }

    EndTimeReminderService.instance.attachPlugin(LocalNotifications.plugin);

    try {
      await _applyEndTimeReminderFromPrefs();
    } catch (e) {
      debugPrint('[STARTUP] EndTimeReminderService init error: $e');
    }

    try {
      await ChillStore.instance.init();
    } catch (e) {
      debugPrint('[STARTUP] ChillStore init error: $e');
    }

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'ParkinWorkin',
        notificationText: '포그라운드에서 대기 중',
        callback: myForegroundCallback,
      );
    } catch (e) {
      debugPrint('[STARTUP] startService error: $e');
    }
  }

  static Future<void> _applyEndTimeReminderFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
  }
}
