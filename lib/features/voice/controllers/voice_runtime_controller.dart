import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../../features/account/domain/models/session_account.dart';
import '../../../../../services/firebase_google_auth_bridge.dart';
import '../data/repositories/firestore_voice_channel_repository.dart';
import '../data/repositories/firestore_voice_message_repository.dart';
import '../data/services/voice_audio_playback_service.dart';
import '../data/services/voice_audio_record_service.dart';
import '../domain/models/voice_channel.dart';
import '../domain/models/voice_message.dart';
import '../domain/repositories/voice_channel_repository.dart';
import '../domain/repositories/voice_message_repository.dart';

class VoiceRuntimeController extends ChangeNotifier {
  VoiceRuntimeController._();

  static final VoiceRuntimeController instance =
  VoiceRuntimeController._();

  final WorkinTalkinAudioRecordService _recordService =
      WorkinTalkinAudioRecordService();
  final VoiceAudioPlaybackService _playbackService =
      VoiceAudioPlaybackService();

  VoiceChannelRepository? _channelRepository;
  VoiceMessageRepository? _voiceRepository;
  StreamSubscription<List<voice_message>>? _messagesSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;

  SessionAccount? _activeSession;
  VoiceChannel? _activeChannel;
  List<voice_message> _messages = const [];
  bool _ready = false;
  bool _starting = false;
  bool _active = false;
  bool _isRecording = false;
  bool _isUploading = false;
  bool _didReceiveInitialSnapshot = false;
  String? _errorMessage;
  String? _currentlyPlayingMessageId;
  String? _lastAutoPlayedMessageId;
  String? _lastSeenMessageId;
  DateTime? _recordingStartedAt;
  Duration _playerPosition = Duration.zero;
  Duration _playerDuration = Duration.zero;

  bool get ready => _ready;

  bool get starting => _starting;

  bool get active => _active;

  bool get isRecording => _isRecording;

  bool get isUploading => _isUploading;

  String? get errorMessage => _errorMessage;

  SessionAccount? get activeSession => _activeSession;

  VoiceChannel? get activeChannel => _activeChannel;

  List<voice_message> get messages => _messages;

  String? get currentlyPlayingMessageId => _currentlyPlayingMessageId;

  Duration get playerPosition => _playerPosition;

  Duration get playerDuration => _playerDuration;

  void configureRepositories({
    VoiceChannelRepository? channelRepository,
    VoiceMessageRepository? voiceRepository,
  }) {
    if (channelRepository != null) {
      _channelRepository = channelRepository;
    }
    if (voiceRepository != null) {
      _voiceRepository = voiceRepository;
    }
  }

  Future<void> initialize() async {
    if (_ready) {
      return;
    }
    _channelRepository ??= FirestoreVoiceChannelRepository();
    _voiceRepository ??= FirestoreVoiceMessageRepository();
    _bindPlayerStreams();
    _ready = true;
    notifyListeners();
  }

  Future<void> start({
    required SessionAccount session,
    required String areaName,
  }) async {
    await initialize();
    if (_starting) {
      return;
    }
    _starting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await FirebaseGoogleAuthBridge.instance.configureRuntime();
      if (FirebaseAuth.instance.currentUser == null) {
        final ok = await FirebaseGoogleAuthBridge.instance.bootstrap(
          interactive: false,
        );
        if (!ok || FirebaseAuth.instance.currentUser == null) {
          throw Exception('Firebase 인증 세션을 준비하지 못했습니다.');
        }
      }
      final area = areaName.trim();
      if (area.isEmpty) {
        throw Exception('currentArea 값이 비어 있습니다.');
      }
      final channel = await _channelRepository!.ensureForArea(area);
      final channelChanged = _activeChannel?.id != channel.id;
      _activeSession = session;
      _activeChannel = channel;
      _active = true;
      if (channelChanged) {
        await _messagesSubscription?.cancel();
        _messagesSubscription = null;
        await _playbackService.stop();
        _messages = const [];
        _currentlyPlayingMessageId = null;
        _playerPosition = Duration.zero;
        _playerDuration = Duration.zero;
        _lastAutoPlayedMessageId = null;
        _lastSeenMessageId = null;
        _didReceiveInitialSnapshot = false;
        _messagesSubscription =
            _voiceRepository!.watchMessages(channel.id).listen(_handleMessages);
      }
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      _active = false;
      notifyListeners();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    await _playbackService.stop();
    _active = false;
    _activeSession = null;
    _activeChannel = null;
    _messages = const [];
    _isRecording = false;
    _isUploading = false;
    _didReceiveInitialSnapshot = false;
    _currentlyPlayingMessageId = null;
    _lastAutoPlayedMessageId = null;
    _lastSeenMessageId = null;
    _playerPosition = Duration.zero;
    _playerDuration = Duration.zero;
    notifyListeners();
  }

  Future<void> startRecording() async {
    if (!_active ||
        _isRecording ||
        _isUploading ||
        _activeSession == null ||
        _activeChannel == null) {
      return;
    }
    _errorMessage = null;
    try {
      await _recordService.start();
      _recordingStartedAt = DateTime.now();
      _isRecording = true;
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) {
      return;
    }
    await _recordService.cancel();
    _recordingStartedAt = null;
    _isRecording = false;
    notifyListeners();
  }

  Future<void> stopRecordingAndSend() async {
    final session = _activeSession;
    final channel = _activeChannel;
    final repository = _voiceRepository;
    if (!_isRecording ||
        session == null ||
        channel == null ||
        repository == null) {
      return;
    }
    _isRecording = false;
    _isUploading = true;
    _errorMessage = null;
    notifyListeners();
    File? file;
    try {
      file = await _recordService.stop();
      if (file == null) {
        throw Exception('녹음 파일을 만들지 못했습니다.');
      }
      final startedAt = _recordingStartedAt ?? DateTime.now();
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      if (durationMs < 500) {
        throw Exception('0.5초 이상 녹음해 주세요.');
      }
      await repository.sendMessage(
        channel: channel,
        session: session,
        audioFile: file,
        durationMs: durationMs,
      );
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _recordingStartedAt = null;
      _isUploading = false;
      if (file != null && await file.exists()) {
        await file.delete();
      }
      notifyListeners();
    }
  }

  Future<void> togglePlayback(voice_message message) async {
    if (_currentlyPlayingMessageId == message.id) {
      await _playbackService.stop();
      _currentlyPlayingMessageId = null;
      _playerPosition = Duration.zero;
      notifyListeners();
      return;
    }
    _errorMessage = null;
    _currentlyPlayingMessageId = message.id;
    _playerPosition = Duration.zero;
    _playerDuration = message.duration;
    notifyListeners();
    try {
      await _playbackService.playUrl(message.audioUrl);
    } catch (error) {
      _errorMessage = error.toString();
      _currentlyPlayingMessageId = null;
      notifyListeners();
    }
  }

  Future<void> playPreviousComment() async {
    if (_messages.isEmpty) {
      return;
    }
    final target = _messages.length > 1 ? _messages[1] : _messages.first;
    await togglePlayback(target);
  }

  Future<void> deleteMessage(voice_message message) async {
    final session = _activeSession;
    final channel = _activeChannel;
    final repository = _voiceRepository;
    if (session == null || channel == null || repository == null) {
      return;
    }
    final canDeleteAnyMessage = session.role.contains('admin');
    if (message.senderId != session.id && !canDeleteAnyMessage) {
      _errorMessage = '본인이 보낸 음성만 삭제할 수 있습니다.';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    try {
      if (_currentlyPlayingMessageId == message.id) {
        await _playbackService.stop();
        _currentlyPlayingMessageId = null;
      }
      await repository.deleteMessage(channel.id, message);
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  void _bindPlayerStreams() {
    _playerStateSubscription ??=
        _playbackService.playerStateStream.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        _currentlyPlayingMessageId = null;
        _playerPosition = Duration.zero;
        notifyListeners();
      }
    });
    _playerPositionSubscription ??=
        _playbackService.positionStream.listen((position) {
      _playerPosition = position;
      notifyListeners();
    });
    _playerDurationSubscription ??=
        _playbackService.durationStream.listen((duration) {
      _playerDuration = duration;
      notifyListeners();
    });
  }

  void _handleMessages(List<voice_message> nextMessages) {
    _messages = nextMessages;
    final latest = nextMessages.isNotEmpty ? nextMessages.first : null;
    if (latest != null) {
      final isInitialSnapshot = !_didReceiveInitialSnapshot;
      _didReceiveInitialSnapshot = true;
      final wasSeenBefore = _lastSeenMessageId == latest.id;
      _lastSeenMessageId = latest.id;
      final shouldAutoPlay = !isInitialSnapshot &&
          _active &&
          !wasSeenBefore &&
          latest.senderId != _activeSession?.id &&
          latest.audioUrl.isNotEmpty &&
          latest.id != _lastAutoPlayedMessageId &&
          !_isRecording &&
          !_isUploading;
      if (shouldAutoPlay) {
        _lastAutoPlayedMessageId = latest.id;
        unawaited(togglePlayback(latest));
      }
    }
    notifyListeners();
  }

  Future<void> close() async {
    await _messagesSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    await _playerPositionSubscription?.cancel();
    await _playerDurationSubscription?.cancel();
    await _recordService.dispose();
    await _playbackService.dispose();
  }
}
