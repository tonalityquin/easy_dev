import 'chat_message.dart';

class ChatSearchPage {
  const ChatSearchPage({
    required this.messages,
    required this.nextBeforeSeq,
    required this.hasMore,
    required this.scannedCount,
  });

  final List<ChatMessage> messages;
  final int? nextBeforeSeq;
  final bool hasMore;
  final int scannedCount;
}
