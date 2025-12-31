// lib/services/chat_local_notification_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 앱이 "열려 있어도" OS 알림처럼 보이도록(특히 iOS 포그라운드) 설정한 로컬 알림 서비스.
/// - Android: Heads-up(채널 중요도 HIGH) 가능
/// - iOS: DarwinNotificationDetails(presentAlert:true)로 포그라운드에서도 배너 표시(권한 필요)
class ChatLocalNotificationService {
  ChatLocalNotificationService._();

  static final ChatLocalNotificationService instance =
  ChatLocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Android 채널
  static const String _channelId = 'chat_messages';
  static const String _channelName = 'Chat Messages';
  static const String _channelDesc = 'Notifications for new chat messages';

  // 중복/자기 메시지 억제(선택)
  String? _lastSelfSentText;
  DateTime? _lastSelfSentAt;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(settings);

    // Android 채널 생성
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      );
      await android.createNotificationChannel(channel);
    }

    // 권한 요청
    await requestPermissions();

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+ POST_NOTIFICATIONS 런타임 권한
      await android?.requestNotificationsPermission();
      return;
    }

    // iOS / macOS 구현체는 각각 존재
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return;
    }

    if (Platform.isMacOS) {
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await mac?.requestPermissions(alert: true, badge: true, sound: true);
      return;
    }
  }

  /// (선택) 내가 방금 보낸 텍스트를 기록해 두면,
  /// 폴링으로 다시 들어온 동일 텍스트에 대해 "자기 알림"을 억제할 수 있습니다.
  void markSelfSent(String text) {
    _lastSelfSentText = text.trim();
    _lastSelfSentAt = DateTime.now();
  }

  bool isLikelySelfSent(String text) {
    final t = text.trim();
    if (_lastSelfSentText == null || _lastSelfSentAt == null) return false;
    if (t != _lastSelfSentText) return false;

    final diff = DateTime.now().difference(_lastSelfSentAt!);
    return diff.inSeconds <= 12; // 폴링 지연 고려
  }

  Future<void> showChatMessage({
    required String scopeKey,
    required String message,
    int? countHint, // 다건 요약 시 title에 N개 힌트
  }) async {
    await ensureInitialized();

    final scope = scopeKey.trim();
    final title = (countHint != null && countHint > 1)
        ? '구역 채팅 ($scope) • $countHint'
        : '구역 채팅 ($scope)';

    final body = message.trim().isEmpty ? '(빈 메시지)' : message.trim();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    // iOS: 포그라운드에서도 배너/사운드/뱃지 표시(사용자 권한 필요)
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

    await _plugin.show(
      id,
      title,
      body,
      details,
      payload: scope,
    );
  }
}
