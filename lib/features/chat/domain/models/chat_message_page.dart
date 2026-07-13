import 'chat_message.dart';

class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
}
