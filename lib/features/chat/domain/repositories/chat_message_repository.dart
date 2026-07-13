import '../../../account/domain/models/session_account.dart';
import '../models/chat_channel.dart';
import '../models/chat_message.dart';
import '../models/chat_message_page.dart';
import '../models/chat_search_index_batch.dart';
import '../models/chat_search_page.dart';

abstract class ChatMessageRepository {
  Stream<List<ChatMessage>> watchLatestMessages(
    String channelId, {
    int limit,
  });

  Future<ChatMessagePage> fetchOlderMessages(
    String channelId, {
    required int beforeSeq,
    int limit,
  });

  Future<ChatSearchPage> searchMessages(
    String channelId, {
    required String query,
    int? beforeSeq,
    int limit,
  });

  Future<ChatSearchIndexBatch> indexSearchHistory(
    String channelId, {
    int? beforeSeq,
    int limit,
  });

  Stream<ChatMessageChangeBatch> watchRecentChanges(
    String channelId, {
    int limit,
  });

  Future<void> sendMessage({
    required ChatChannel channel,
    required SessionAccount session,
    required String text,
  });
}
