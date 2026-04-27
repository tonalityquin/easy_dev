import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class LocalNotifications {
  static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Completer<void>? _inFlight;

  static Future<void> ensureInitialized() async {
    if (_ready) return;
    if (_inFlight != null) return _inFlight!.future;

    final c = Completer<void>();
    _inFlight = c;

    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (resp) {},
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidImpl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        const channel = AndroidNotificationChannel(
          'ParkinWorkin_reminders',
          '근무 리마인더',
          description: '퇴근 1시간 전 알림 채널',
          importance: Importance.high,
        );
        await androidImpl?.createNotificationChannel(channel);
      }

      _ready = true;
      c.complete();
    } catch (e, st) {
      if (!c.isCompleted) {
        c.completeError(e, st);
      }
    } finally {
      _inFlight = null;
    }
  }

  static Future<bool?> isPermissionGranted() async {
    await ensureInitialized();
    if (kIsWeb) return null;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.areNotificationsEnabled();
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return null;
    }

    return null;
  }

  static Future<bool?> requestPermission() async {
    await ensureInitialized();
    if (kIsWeb) return null;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidImpl?.areNotificationsEnabled();
      if (enabled == true) return true;
      await androidImpl?.requestNotificationsPermission();
      return await androidImpl?.areNotificationsEnabled();
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImpl = plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
    }

    return null;
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse resp) {}
