class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.seq,
    required this.senderId,
    required this.senderName,
    required this.senderIdentity,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final int seq;
  final String senderId;
  final String senderName;
  final String senderIdentity;
  final String text;
  final DateTime createdAt;
}
