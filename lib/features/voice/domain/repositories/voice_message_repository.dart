import 'dart:io';
import '../../../../../features/account/domain/models/session_account.dart';
import '../models/voice_channel.dart';
import '../models/voice_message.dart';

abstract class VoiceMessageRepository {
  Stream<List<voice_message>> watchMessages(String channelId);

  Future<void> sendMessage({
    required VoiceChannel channel,
    required SessionAccount session,
    required File audioFile,
    required int durationMs,
  });

  Future<void> deleteMessage(
    String channelId,
    voice_message message,
  );

  Future<void> pruneOldMessages(String channelId);
}
