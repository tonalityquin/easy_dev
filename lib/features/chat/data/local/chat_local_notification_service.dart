import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/models/chat_message.dart';

class ChatLocalNotificationService {
  ChatLocalNotificationService._();

  static final ChatLocalNotificationService instance =
      ChatLocalNotificationService._();

  static const String _channelId = 'area_chat_channel';
  static const String _channelName = 'Area Chat Alerts';
  static const String _channelDesc = '지역별 채팅 신규 메시지 알림';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static Completer<void>? _inFlight;

  Future<void> ensureInitialized() async {
    if (_ready) return;
    if (_inFlight != null) return _inFlight!.future;

    final completer = Completer<void>();
    _inFlight = completer;

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: androidInit, iOS: iosInit);
      await _plugin.initialize(settings);

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

      _ready = true;
      completer.complete();
    } catch (e, st) {
      debugPrint('[ChatNotif] init failed: $e\n$st');
      if (!completer.isCompleted) completer.complete();
    } finally {
      _inFlight = null;
    }
  }

  int _makeId(ChatMessage message) {
    final value = '${message.areaKey}:${message.id}'.hashCode ^ 31;
    return value & 0x7fffffff;
  }

  Future<void> showChatMessage(ChatMessage message) async {
    await ensureInitialized();

    final area = message.areaName.trim();
    final sender = message.senderName.trim().isEmpty
        ? '새 메시지'
        : message.senderName.trim();
    final text = message.text.trim().isEmpty ? '(내용 없음)' : message.text.trim();
    final title = area.isEmpty ? '채팅 새 메시지' : '$area 채팅 새 메시지';
    final body = '$sender: $text';

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

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        _makeId(message),
        title,
        body,
        details,
        payload: message.areaName,
      );
    } catch (e, st) {
      debugPrint('[ChatNotif] show failed: $e\n$st');
    }
  }
}
