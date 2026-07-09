import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.areaKey,
    required this.areaName,
    required this.senderId,
    required this.senderName,
    required this.senderIdentity,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String areaKey;
  final String areaName;
  final String senderId;
  final String senderName;
  final String senderIdentity;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    final rawId = data['id'];
    final storedId = rawId is String ? rawId.trim() : '';
    final rawAreaKey = data['areaKey'];
    final rawAreaName = data['areaName'];
    final rawSenderId = data['senderId'];
    final rawSenderName = data['senderName'];
    final rawSenderIdentity = data['senderIdentity'];
    final rawText = data['text'];

    return ChatMessage(
      id: storedId.isNotEmpty ? storedId : id,
      areaKey: rawAreaKey is String ? rawAreaKey.trim() : '',
      areaName: rawAreaName is String ? rawAreaName.trim() : '',
      senderId: rawSenderId is String ? rawSenderId.trim() : '',
      senderName: rawSenderName is String ? rawSenderName.trim() : '',
      senderIdentity: rawSenderIdentity is String ? rawSenderIdentity.trim() : '',
      text: rawText is String ? rawText.trim() : '',
      createdAt: _readDate(data['createdAt']),
    );
  }

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }
}

class ChatMessageChange {
  const ChatMessageChange({
    required this.type,
    required this.message,
  });

  final DocumentChangeType type;
  final ChatMessage message;
}

class ChatMessageChangeBatch {
  const ChatMessageChangeBatch({
    required this.isFromCache,
    required this.hasPendingWrites,
    required this.changes,
  });

  final bool isFromCache;
  final bool hasPendingWrites;
  final List<ChatMessageChange> changes;
}
