import 'package:cloud_firestore/cloud_firestore.dart';

class ChatPinnedNotice {
  const ChatPinnedNotice({
    required this.messageId,
    required this.seq,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderIdentity,
    required this.pinnedBy,
    required this.pinnedAt,
  });

  final String messageId;
  final int seq;
  final String text;
  final String senderId;
  final String senderName;
  final String senderIdentity;
  final String pinnedBy;
  final DateTime? pinnedAt;

  factory ChatPinnedNotice.fromMap(Map<String, dynamic> data) {
    final rawMessageId = data['messageId'];
    final rawText = data['text'];
    final rawSenderId = data['senderId'];
    final rawSenderName = data['senderName'];
    final rawSenderIdentity = data['senderIdentity'];
    final rawPinnedBy = data['pinnedBy'];

    return ChatPinnedNotice(
      messageId: rawMessageId is String ? rawMessageId.trim() : '',
      seq: _readInt(data['seq']),
      text: rawText is String ? rawText.trim() : '',
      senderId: rawSenderId is String ? rawSenderId.trim() : '',
      senderName: rawSenderName is String ? rawSenderName.trim() : '',
      senderIdentity:
          rawSenderIdentity is String ? rawSenderIdentity.trim() : '',
      pinnedBy: rawPinnedBy is String ? rawPinnedBy.trim() : '',
      pinnedAt: _readDateOrNull(data['pinnedAt']),
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
