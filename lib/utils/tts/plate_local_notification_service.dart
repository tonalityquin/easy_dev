import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';





class PlateLocalNotificationService {
  PlateLocalNotificationService._();

  static final PlateLocalNotificationService instance = PlateLocalNotificationService._();

  static const String _channelId = 'plate_tts_channel';
  static const String _channelName = 'Plate TTS Alerts';
  static const String _channelDesc = '번호판 이벤트(입차/출차/완료) 알림';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static Completer<void>? _inFlight;

  
  Future<void> ensureInitialized() async {
    if (_ready) return;
    if (_inFlight != null) return _inFlight!.future;

    final c = Completer<void>();
    _inFlight = c;

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const settings = InitializationSettings(android: androidInit, iOS: iosInit);
      await _plugin.initialize(settings);

      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        );
        await android.createNotificationChannel(channel);
      }

      _ready = true;
      c.complete();
    } catch (e, st) {
      debugPrint('[PlateNotif] init failed: $e\n$st');
      if (!c.isCompleted) c.complete();
    } finally {
      _inFlight = null;
    }
  }

  
  int _makeId(String docId, {int salt = 17}) {
    
    final int v = docId.hashCode ^ salt;
    return v & 0x7fffffff;
  }

  Future<void> showPlateEvent({
    required String docId,
    required String title,
    required String plateNumber,
    required String parkingLocation,
    String? area,
  }) async {
    await ensureInitialized();

    final a = (area ?? '').trim();
    final p = plateNumber.trim().isEmpty ? '(차량번호 없음)' : plateNumber.trim();
    final loc = parkingLocation.trim().isEmpty ? '(주차구역 미지정)' : parkingLocation.trim();

    final String finalTitle = a.isEmpty ? title : '$title ($a)';
    final String body = '차량번호: $p\n주차구역: $loc';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      await _plugin.show(
        _makeId(docId),
        finalTitle,
        body,
        details,
        payload: a.isEmpty ? null : a,
      );
    } catch (e, st) {
      debugPrint('[PlateNotif] show failed: $e\n$st');
    }
  }
}
