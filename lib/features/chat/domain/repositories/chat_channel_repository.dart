import '../../../account/domain/models/session_account.dart';
import '../models/chat_channel.dart';
import '../models/chat_message.dart';

abstract class ChatChannelRepository {
  ChatChannel channelForArea({
    required String division,
    required String areaName,
    required bool isHeadquarter,
  });

  Future<ChatChannel> ensureForArea({
    required String division,
    required String areaName,
    required bool isHeadquarter,
  });

  Stream<ChatChannel> watchChannel(ChatChannel channel);

  Stream<ChatChannelChangeBatch> watchChannelBatchByChannelIds(
    List<String> channelIds,
  );

  Future<void> pinNotice({
    required ChatChannel channel,
    required ChatMessage message,
    required SessionAccount session,
  });

  Future<void> clearPinnedNotice({
    required ChatChannel channel,
    required SessionAccount session,
  });
}
