import 'package:audioplayers/audioplayers.dart';

class VoiceAudioPlaybackService {
  VoiceAudioPlaybackService() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setPlayerMode(PlayerMode.mediaPlayer);
  }

  final AudioPlayer _player = AudioPlayer();

  Stream<PlayerState> get playerStateStream => _player.onPlayerStateChanged;
  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream => _player.onDurationChanged;

  Future<void> playUrl(String url) async {
    await _player.stop();
    await _player.play(UrlSource(url));
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}
