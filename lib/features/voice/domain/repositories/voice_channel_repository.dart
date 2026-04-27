import '../models/voice_channel.dart';

abstract class VoiceChannelRepository {
  Future<VoiceChannel> ensureForArea(String areaName);
}
