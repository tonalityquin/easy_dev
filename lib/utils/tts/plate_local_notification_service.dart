import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Plate(번호판) 이벤트용 로컬 알림 서비스.
///
/// - 채팅 알림과 동일하게 heads-up(Importance.high / Priority.high)로 노출
/// - FG isolate(포그라운드 서비스)에서도 사용할 수 있도록 "isolate-safe" 초기화 제공
class PlateLocalNotificationService {
  PlateLocalNotificationService._();

  static final PlateLocalNotificationService instance = PlateLocalNotificationService._();

  static const String _channelId = 'plate_tts_channel';
  static const String _channelName = 'Plate TTS Alerts';
  static const String _channelDesc = '번호판 이벤트(입차/출차/완료) 알림';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static Completer<void>? _inFlight;

  /// 여러 isolate에서 중복 호출되어도 안전하게 1회만 초기화되도록 게이트합니다.
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

  /// docId 기반으로 비교적 안정적인 notification id를 생성합니다.
  int _makeId(String docId, {int salt = 17}) {
    // String.hashCode는 세션 내 안정적이며, 알림 ID로는 충분합니다.
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
