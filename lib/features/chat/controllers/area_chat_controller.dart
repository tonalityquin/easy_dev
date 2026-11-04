import 'package:flutter/foundation.dart';

import '../../account/domain/models/session_account.dart';
import '../application/chat_account_scope.dart';
import '../application/chat_area_key.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/chat_pinned_notice.dart';

class AreaChatController extends ChangeNotifier {
  static final Map<String, List<ChatMessage>> _messagesByChannel =
      <String, List<ChatMessage>>{};
  static final Map<String, ChatPinnedNotice?> _noticeByChannel =
      <String, ChatPinnedNotice?>{};

  SessionAccount? _session;
  String _channelId = '';
  String _areaName = '';
  bool _isHeadquarterChannel = false;
  bool _accessAllowed = false;
  bool _sending = false;
  String _searchQuery = '';

  List<ChatMessage> get messages {
    final source = _messagesByChannel[_channelId] ?? const <ChatMessage>[];
    return List<ChatMessage>.unmodifiable(source);
  }

  List<ChatMessage> get searchResults {
    final query = _normalize(_searchQuery);
    if (query.isEmpty) return messages;
    final terms = query
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    return messages.where((message) {
      final source = _normalize(
        '${message.senderName} ${message.senderIdentity} ${message.text}',
      );
      return terms.every(source.contains);
    }).toList(growable: false);
  }

  String get areaName => _areaName;
  String get channelId => _channelId;
  String get currentUserId => _session?.id.trim() ?? '';
  String get currentUserName => _session?.displayName.trim() ?? '';
  String get currentUserIdentity {
    final session = _session;
    if (session == null) return '';
    final position = session.position?.trim() ?? '';
    if (position.isNotEmpty) return position;
    return session.role.trim();
  }

  bool get isHeadquarterChannel => _isHeadquarterChannel;
  bool get accessAllowed => _accessAllowed;
  bool get sending => _sending;
  String get searchQuery => _searchQuery;
  bool get hasSearchQuery => _searchQuery.trim().isNotEmpty;
  ChatPinnedNotice? get pinnedNotice => _noticeByChannel[_channelId];
  int get latestSeq => messages.isEmpty ? 0 : messages.last.seq;

  Future<void> start({
    required SessionAccount session,
    required String areaName,
    required bool isHeadquarterChannel,
  }) async {
    final scope = ChatAccountScope.fromSession(session);
    final normalizedArea = isHeadquarterChannel
        ? headquarterChatAreaName
        : areaName.trim();
    final channelId = scope.channelIdFor(
      areaName: normalizedArea,
      isHeadquarterChannel: isHeadquarterChannel,
    );

    _session = session;
    _areaName = normalizedArea;
    _isHeadquarterChannel = isHeadquarterChannel;
    _channelId = channelId;
    _accessAllowed = scope.canAccessChannel(
      areaName: normalizedArea,
      isHeadquarterChannel: isHeadquarterChannel,
    );
    _searchQuery = '';

    if (_accessAllowed && _channelId.isNotEmpty) {
      _messagesByChannel.putIfAbsent(_channelId, () => <ChatMessage>[]);
      _noticeByChannel.putIfAbsent(_channelId, () => null);
    }

    notifyListeners();
  }

  Future<void> stop() async {
    _session = null;
    _channelId = '';
    _areaName = '';
    _isHeadquarterChannel = false;
    _accessAllowed = false;
    _sending = false;
    _searchQuery = '';
    notifyListeners();
  }

  void setSearchQuery(String value) {
    final next = value.trimLeft();
    if (_searchQuery == next) return;
    _searchQuery = next;
    notifyListeners();
  }

  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    notifyListeners();
  }

  Future<bool> sendText(String rawText) async {
    final text = rawText.trim();
    final session = _session;
    if (text.isEmpty || session == null || !_accessAllowed) return false;
    if (_channelId.isEmpty || _sending) return false;

    _sending = true;
    notifyListeners();

    try {
      final target = _messagesByChannel.putIfAbsent(
        _channelId,
        () => <ChatMessage>[],
      );
      final seq = target.isEmpty ? 1 : target.last.seq + 1;
      final now = DateTime.now();
      target.add(
        ChatMessage(
          id: '${now.microsecondsSinceEpoch}-$seq',
          seq: seq,
          senderId: session.id.trim(),
          senderName: session.displayName.trim().isEmpty
              ? '사용자'
              : session.displayName.trim(),
          senderIdentity: currentUserIdentity,
          text: text,
          createdAt: now,
        ),
      );
      return true;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void pinMessage(ChatMessage message) {
    if (!_accessAllowed || _channelId.isEmpty) return;
    _noticeByChannel[_channelId] = ChatPinnedNotice.fromMessage(
      message: message,
      pinnedBy: currentUserId,
    );
    notifyListeners();
  }

  void clearPinnedNotice() {
    if (!_accessAllowed || _channelId.isEmpty) return;
    if (_noticeByChannel[_channelId] == null) return;
    _noticeByChannel[_channelId] = null;
    notifyListeners();
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
