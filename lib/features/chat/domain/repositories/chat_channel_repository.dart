import '../models/chat_channel.dart';

abstract class ChatChannelRepository {
  ChatChannel channelForArea(String areaName);

  Future<ChatChannel> ensureForArea(String areaName);

  Stream<ChatChannelChangeBatch> watchChannelBatchByAreaKeys(
    List<String> areaKeys,
  );
}
