import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../account/domain/models/session_account.dart';
import '../application/area_chat_read_receipts.dart';
import '../data/repositories/firestore_chat_channel_repository.dart';
import '../data/repositories/firestore_chat_message_repository.dart';
import '../domain/models/chat_channel.dart';
import '../domain/models/chat_message.dart';
import '../domain/repositories/chat_channel_repository.dart';
import '../domain/repositories/chat_message_repository.dart';

class AreaChatController extends ChangeNotifier {
  AreaChatController({
    ChatChannelRepository? channelRepository,
    ChatMessageRepository? messageRepository,
  })  : _channelRepository =
            channelRepository ?? FirestoreChatChannelRepository(),
        _messageRepository =
            messageRepository ?? FirestoreChatMessageRepository();

  final ChatChannelRepository _channelRepository;
  final ChatMessageRepository _messageRepository;

  StreamSubscription<List<ChatMessage>>? _subscription;
  SessionAccount? _session;
  ChatChannel? _channel;
  String _areaName = '';
  List<ChatMessage> _messages = const [];
  bool _loading = false;
  bool _sending = false;
  String? _errorText;

  List<ChatMessage> get messages => _messages;
  bool get loading => _loading;
  bool get sending => _sending;
  String? get errorText => _errorText;
  String get areaName => _areaName;
  String? get sessionId => _session?.id;

  Future<void> start({
    required SessionAccount session,
    required String areaName,
  }) async {
    final cleanArea = areaName.trim();
    if (cleanArea.isEmpty) {
      await stop();
      _errorText = '지역 정보가 없습니다.';
      notifyListeners();
      return;
    }

    final alreadyBound =
        _session?.id == session.id && _areaName == cleanArea && _channel != null;
    if (alreadyBound) return;

    await _subscription?.cancel();
    _subscription = null;
    _session = session;
    _areaName = cleanArea;
    _channel = null;
    _messages = const [];
    _loading = true;
    _errorText = null;
    notifyListeners();

    try {
      final channel = _channelRepository.channelForArea(cleanArea);
      _channel = channel;
      _subscription = _messageRepository.watchMessages(channel.id, limit: 50).listen(
        (messages) {
          _messages = messages;
          _loading = false;
          _errorText = null;
          notifyListeners();
          final readSeq = messages.isEmpty ? 0 : messages.last.seq;
          unawaited(AreaChatReadReceipts.markRead(cleanArea, seq: readSeq));
        },
        onError: (Object error) {
          _loading = false;
          _errorText = '$error';
          notifyListeners();
        },
      );
    } catch (e) {
      _loading = false;
      _errorText = '$e';
      notifyListeners();
    }
  }

  Future<void> sendText(String text) async {
    final clean = text.trim();
    final session = _session;
    final channel = _channel;
    if (clean.isEmpty || session == null || channel == null || _sending) {
      return;
    }

    _sending = true;
    _errorText = null;
    notifyListeners();

    try {
      await _messageRepository.sendMessage(
        channel: channel,
        session: session,
        text: clean,
      );
    } catch (e) {
      _errorText = '$e';
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _session = null;
    _channel = null;
    _areaName = '';
    _messages = const [];
    _loading = false;
    _sending = false;
    _errorText = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
