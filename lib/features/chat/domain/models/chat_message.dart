import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/chat_area_key.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.division,
    required this.companyKey,
    required this.channelType,
    required this.areaKey,
    required this.areaName,
    required this.seq,
    required this.senderId,
    required this.senderName,
    required this.senderIdentity,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String channelId;
  final String division;
  final String companyKey;
  final String channelType;
  final String areaKey;
  final String areaName;
  final int seq;
  final String senderId;
  final String senderName;
  final String senderIdentity;
  final String text;
  final DateTime createdAt;

  bool get isHeadquarter => channelType == chatChannelTypeHeadquarter;

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    final storedId = _readString(data['id']);
    return ChatMessage(
      id: storedId.isNotEmpty ? storedId : id,
      channelId: _readString(data['channelId']),
      division: _readString(data['division']),
      companyKey: _readString(data['companyKey']),
      channelType: _readString(data['channelType']) ==
                  chatChannelTypeHeadquarter ||
              _readString(data['areaKey']) == headquarterChatAreaKey
          ? chatChannelTypeHeadquarter
          : chatChannelTypeArea,
      areaKey: _readString(data['areaKey']),
      areaName: _readString(data['areaName']),
      seq: _readInt(data['seq']),
      senderId: _readString(data['senderId']),
      senderName: _readString(data['senderName']),
      senderIdentity: _readString(data['senderIdentity']),
      text: _readString(data['text']),
      createdAt: _readDate(data['createdAt']),
    );
  }

  static String _readString(dynamic value) {
    return value is String ? value.trim() : '';
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
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
