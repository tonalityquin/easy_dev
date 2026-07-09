import 'package:cloud_firestore/cloud_firestore.dart';

class ChatChannel {
  const ChatChannel({
    required this.id,
    required this.areaName,
    required this.areaKey,
    required this.lastMessageId,
    required this.lastMessageText,
    required this.lastSenderId,
    required this.lastSenderName,
    required this.lastSenderIdentity,
    required this.lastMessageCreatedAt,
    required this.messageSeq,
    required this.messageCount,
    required this.updatedAt,
  });

  final String id;
  final String areaName;
  final String areaKey;
  final String lastMessageId;
  final String lastMessageText;
  final String lastSenderId;
  final String lastSenderName;
  final String lastSenderIdentity;
  final DateTime? lastMessageCreatedAt;
  final int messageSeq;
  final int messageCount;
  final DateTime? updatedAt;

  bool get hasMessage => lastMessageId.trim().isNotEmpty && messageSeq > 0;

  factory ChatChannel.empty({
    required String id,
    required String areaName,
    required String areaKey,
  }) {
    return ChatChannel(
      id: id,
      areaName: areaName,
      areaKey: areaKey,
      lastMessageId: '',
      lastMessageText: '',
      lastSenderId: '',
      lastSenderName: '',
      lastSenderIdentity: '',
      lastMessageCreatedAt: null,
      messageSeq: 0,
      messageCount: 0,
      updatedAt: null,
    );
  }

  factory ChatChannel.fromMap(String id, Map<String, dynamic> data) {
    final rawAreaKey = data['areaKey'];
    final rawAreaName = data['areaName'];
    final rawLastMessageId = data['lastMessageId'];
    final rawLastMessageText = data['lastMessageText'];
    final rawLastSenderId = data['lastSenderId'];
    final rawLastSenderName = data['lastSenderName'];
    final rawLastSenderIdentity = data['lastSenderIdentity'];
    final seq = _readInt(data['messageSeq']);
    final count = _readInt(data['messageCount']);

    return ChatChannel(
      id: id.trim(),
      areaName: rawAreaName is String ? rawAreaName.trim() : '',
      areaKey: rawAreaKey is String ? rawAreaKey.trim() : id.trim(),
      lastMessageId: rawLastMessageId is String ? rawLastMessageId.trim() : '',
      lastMessageText: rawLastMessageText is String ? rawLastMessageText.trim() : '',
      lastSenderId: rawLastSenderId is String ? rawLastSenderId.trim() : '',
      lastSenderName: rawLastSenderName is String ? rawLastSenderName.trim() : '',
      lastSenderIdentity: rawLastSenderIdentity is String ? rawLastSenderIdentity.trim() : '',
      lastMessageCreatedAt: _readDateOrNull(data['lastMessageCreatedAt']) ?? _readDateOrNull(data['updatedAt']),
      messageSeq: seq,
      messageCount: count > 0 ? count : seq,
      updatedAt: _readDateOrNull(data['updatedAt']),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static DateTime? _readDateOrNull(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}

class ChatChannelChange {
  const ChatChannelChange({
    required this.type,
    required this.channel,
  });

  final DocumentChangeType type;
  final ChatChannel channel;
}

class ChatChannelChangeBatch {
  const ChatChannelChangeBatch({
    required this.isFromCache,
    required this.hasPendingWrites,
    required this.channels,
    required this.changes,
  });

  final bool isFromCache;
  final bool hasPendingWrites;
  final List<ChatChannel> channels;
  final List<ChatChannelChange> changes;
}
