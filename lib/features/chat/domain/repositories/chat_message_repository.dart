import '../../../account/domain/models/session_account.dart';
import '../models/chat_channel.dart';
import '../models/chat_message.dart';

abstract class ChatMessageRepository {
  Stream<List<ChatMessage>> watchMessages(String channelId, {int limit});

  Stream<ChatMessageChangeBatch> watchRecentChanges(String channelId, {int limit});

  Future<void> sendMessage({
    required ChatChannel channel,
    required SessionAccount session,
    required String text,
  });
}
