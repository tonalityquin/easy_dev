import '../models/chat_channel.dart';

abstract class ChatChannelRepository {
  Future<ChatChannel> ensureForArea(String areaName);
}
