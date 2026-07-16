import 'chat_message.dart';

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
  final DateTime pinnedAt;

  factory ChatPinnedNotice.fromMessage({
    required ChatMessage message,
    required String pinnedBy,
  }) {
    return ChatPinnedNotice(
      messageId: message.id,
      seq: message.seq,
      text: message.text,
      senderId: message.senderId,
      senderName: message.senderName,
      senderIdentity: message.senderIdentity,
      pinnedBy: pinnedBy.trim(),
      pinnedAt: DateTime.now(),
    );
  }
}
