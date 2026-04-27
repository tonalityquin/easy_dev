
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';




class ChatLocalNotificationService {
  ChatLocalNotificationService._();

  static final ChatLocalNotificationService instance =
  ChatLocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  
  static const String _channelId = 'chat_messages';
  static const String _channelName = 'Chat Messages';
  static const String _channelDesc = 'Notifications for new chat messages';

  
  String? _lastSelfSentText;
  DateTime? _lastSelfSentAt;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

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
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      await android?.requestNotificationsPermission();
      return;
    }

    
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

  
  
  void markSelfSent(String text) {
    _lastSelfSentText = text.trim();
    _lastSelfSentAt = DateTime.now();
  }

  bool isLikelySelfSent(String text) {
    final t = text.trim();
    if (_lastSelfSentText == null || _lastSelfSentAt == null) return false;
    if (t != _lastSelfSentText) return false;

    final diff = DateTime.now().difference(_lastSelfSentAt!);
    return diff.inSeconds <= 12; 
  }

  Future<void> showChatMessage({
    required String scopeKey,
    required String message,
    int? countHint, 
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
