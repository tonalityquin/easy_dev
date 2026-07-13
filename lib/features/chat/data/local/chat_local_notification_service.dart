import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/models/chat_channel.dart';
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

  int _makeMessageId(String channelId, String messageId) {
    final value = '$channelId:$messageId'.hashCode ^ 31;
    return value & 0x7fffffff;
  }

  Future<void> showChatMessage(ChatMessage message) async {
    await _show(
      channelId: message.channelId,
      messageId: message.id,
      areaName: message.areaName,
      senderName: message.senderName,
      text: message.text,
    );
  }

  Future<void> showChatChannelSummary(ChatChannel channel) async {
    await _show(
      channelId: channel.id,
      messageId: channel.lastMessageId,
      areaName: channel.areaName,
      senderName: channel.lastSenderName,
      text: channel.lastMessageText,
    );
  }

  Future<void> _show({
    required String channelId,
    required String messageId,
    required String areaName,
    required String senderName,
    required String text,
  }) async {
    await ensureInitialized();

    final area = areaName.trim();
    final sender = senderName.trim().isEmpty ? '새 메시지' : senderName.trim();
    final bodyText = text.trim().isEmpty ? '(내용 없음)' : text.trim();
    final title = area.isEmpty ? '채팅 새 메시지' : '$area 채팅 새 메시지';
    final body = '$sender: $bodyText';

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
        _makeMessageId(channelId, messageId),
        title,
        body,
        details,
        payload: areaName,
      );
    } catch (e, st) {
      debugPrint('[ChatNotif] show failed: $e\n$st');
    }
  }
}
