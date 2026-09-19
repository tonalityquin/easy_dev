import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'live_work_snapshot.dart';

typedef LiveWorkOverdueOpenWorkScreenHandler = void Function(
  String source,
  String payload,
);

class LiveWorkOverdueNotificationService {
  LiveWorkOverdueNotificationService._();

  static final LiveWorkOverdueNotificationService instance =
      LiveWorkOverdueNotificationService._();

  static const int notificationId = 42102;
  static const String channelId = 'parkinworkin_work_overdue_v1';
  static const String channelName = '퇴근 기록 알림';
  static const String channelDescription = '예정 퇴근시간 이후 퇴근 기록을 반복해서 알립니다.';
  static const String openWorkScreenPayload = 'open_work_screen';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _mainIsolateLaunchChecked = false;
  Completer<void>? _initializing;
  LiveWorkOverdueOpenWorkScreenHandler? _openWorkScreenHandler;
  String _lastTapSource = '-';
  String _lastTapPayload = '-';

  bool get isReady => _ready;
  String get lastTapSource => _lastTapSource;
  String get lastTapPayload => _lastTapPayload;

  void setOpenWorkScreenHandler(
    LiveWorkOverdueOpenWorkScreenHandler handler,
  ) {
    _openWorkScreenHandler = handler;
  }

  Future<void> initializeForMainIsolate() async {
    await ensureInitialized();
    if (_mainIsolateLaunchChecked) return;
    _mainIsolateLaunchChecked = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      if (details?.didNotificationLaunchApp == true && response != null) {
        _handleNotificationResponse(response, source: 'cold_start');
      }
      debugPrint(
        '[WORK_OVERDUE] launch checked launched=${details?.didNotificationLaunchApp == true} payload=${response?.payload ?? '-'}',
      );
    } catch (error, stackTrace) {
      debugPrint('[WORK_OVERDUE] launch check error=$error\n$stackTrace');
    }
  }

  Future<void> ensureInitialized() async {
    if (_ready) return;
    if (_initializing != null) return _initializing!.future;
    final completer = Completer<void>();
    _initializing = completer;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (response) {
          _handleNotificationResponse(response, source: 'notification_tap');
        },
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );
      _ready = true;
      debugPrint('[WORK_OVERDUE] initialized');
      completer.complete();
    } catch (error, stackTrace) {
      debugPrint('[WORK_OVERDUE] init error=$error\n$stackTrace');
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    } finally {
      _initializing = null;
    }
  }

  Future<bool> show(LiveWorkSnapshot snapshot) async {
    if (!snapshot.isOverdue || snapshot.scheduledEnd == null) return false;
    try {
      await ensureInitialized();
      final minutes = snapshot.overdueMinutes;
      final body = minutes <= 0
          ? '예정 퇴근시간입니다. 근무 화면에서 퇴근을 기록해 주세요.'
          : '퇴근 기록이 아직 없습니다. 예정 퇴근시간에서 $minutes분 지났습니다.';
      await _plugin.show(
        notificationId,
        '퇴근 기록이 필요합니다',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            onlyAlertOnce: false,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        payload: openWorkScreenPayload,
      );
      debugPrint(
        '[WORK_OVERDUE] notification shown minutes=$minutes scheduledEnd=${snapshot.scheduledEnd!.toIso8601String()} payload=$openWorkScreenPayload',
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('[WORK_OVERDUE] show error=$error\n$stackTrace');
      return false;
    }
  }

  Future<void> cancel() async {
    try {
      await ensureInitialized();
      await _plugin.cancel(notificationId);
      debugPrint('[WORK_OVERDUE] notification cancelled');
    } catch (error, stackTrace) {
      debugPrint('[WORK_OVERDUE] cancel error=$error\n$stackTrace');
    }
  }

  void _handleNotificationResponse(
    NotificationResponse response, {
    required String source,
  }) {
    final payload = response.payload ?? '';
    _lastTapSource = source;
    _lastTapPayload = payload.isEmpty ? '-' : payload;
    debugPrint(
      '[WORK_OVERDUE] notification response source=$source payload=${payload.isEmpty ? '-' : payload} actionId=${response.actionId ?? '-'}',
    );
    if (payload != openWorkScreenPayload) return;
    final handler = _openWorkScreenHandler;
    if (handler == null) {
      debugPrint(
        '[WORK_OVERDUE] open work screen deferred source=$source reason=handler_unavailable',
      );
      return;
    }
    handler(source, payload);
  }
}
