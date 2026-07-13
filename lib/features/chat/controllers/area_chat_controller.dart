import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../account/domain/models/session_account.dart';
import '../application/chat_account_scope.dart';
import '../application/chat_area_key.dart';
import '../application/chat_failure.dart';
import '../application/chat_search_tokens.dart';
import '../data/repositories/firestore_chat_channel_repository.dart';
import '../data/repositories/firestore_chat_message_repository.dart';
import '../domain/models/chat_channel.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/chat_pinned_notice.dart';
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

  static const int pageSize = 10;
  static const int searchIndexBatchSize = 50;

  final ChatChannelRepository _channelRepository;
  final ChatMessageRepository _messageRepository;

  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  StreamSubscription<ChatChannel>? _channelSubscription;
  SessionAccount? _session;
  ChatChannel? _channel;
  String _areaName = '';
  String _division = '';
  bool _isHeadquarterChannel = false;
  List<ChatMessage> _latestMessages = const <ChatMessage>[];
  List<ChatMessage> _olderMessages = const <ChatMessage>[];
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<ChatMessage> _globalSearchResults = const <ChatMessage>[];
  bool _loading = false;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _updatingPinnedNotice = false;
  bool _hasMore = true;
  bool _historyNoticeVisible = false;
  bool _historyGapPending = false;
  int _historyGapAnchorSeq = 0;
  String _searchQuery = '';
  bool _globalSearchActive = false;
  bool _searchingAll = false;
  bool _globalSearchHasMore = false;
  int? _globalSearchNextBeforeSeq;
  int _globalSearchScannedCount = 0;
  bool _indexingSearchHistory = false;
  bool _searchIndexHasMore = true;
  int? _searchIndexNextBeforeSeq;
  int _searchIndexScannedCount = 0;
  int _searchIndexUpdatedCount = 0;
  ChatFailure? _primaryFailure;
  ChatFailure? _historyFailure;
  ChatFailure? _sendFailure;
  ChatFailure? _noticeFailure;
  ChatFailure? _searchFailure;
  ChatFailure? _searchIndexFailure;

  List<ChatMessage> get messages => _messages;
  bool get loading => _loading;
  bool get loadingOlder => _loadingOlder;
  bool get sending => _sending;
  bool get updatingPinnedNotice => _updatingPinnedNotice;
  bool get hasMore => _hasMore;
  bool get historyRebased => _historyNoticeVisible;
  bool get historyGapPending => _historyGapPending;
  String get searchQuery => _searchQuery;
  bool get globalSearchActive => _globalSearchActive;
  bool get searchingAll => _searchingAll;
  bool get globalSearchHasMore => _globalSearchHasMore;
  bool get globalSearchHasCursor => _globalSearchNextBeforeSeq != null;
  int get globalSearchScannedCount => _globalSearchScannedCount;
  bool get indexingSearchHistory => _indexingSearchHistory;
  bool get searchIndexHasMore => _searchIndexHasMore;
  int get searchIndexScannedCount => _searchIndexScannedCount;
  int get searchIndexUpdatedCount => _searchIndexUpdatedCount;
  ChatFailure? get primaryFailure => _primaryFailure;
  ChatFailure? get historyFailure => _historyFailure;
  ChatFailure? get sendFailure => _sendFailure;
  ChatFailure? get noticeFailure => _noticeFailure;
  ChatFailure? get searchFailure => _searchFailure;
  ChatFailure? get searchIndexFailure => _searchIndexFailure;
  String get areaName => _areaName;
  String? get sessionId => _session?.id;
  ChatPinnedNotice? get pinnedNotice => _channel?.pinnedNotice;
  int get latestSeq =>
      _latestMessages.isEmpty ? 0 : _latestMessages.last.seq;
  int get oldestLoadedSeq => _messages.isEmpty ? 0 : _messages.first.seq;

  List<ChatMessage> get localSearchResults {
    final terms = chatSearchTerms(_searchQuery);
    if (terms.isEmpty) return const <ChatMessage>[];
    return _messages.where((message) {
      final source = normalizeChatSearchText(
        '${message.senderName} ${message.senderIdentity} ${message.text}',
      );
      return terms.every(source.contains);
    }).toList(growable: false);
  }

  List<ChatMessage> get searchResults => _globalSearchActive
      ? _globalSearchResults
      : localSearchResults;

  Future<void> start({
    required SessionAccount session,
    required String areaName,
    required bool isHeadquarterChannel,
    bool force = false,
  }) async {
    final accountScope = ChatAccountScope.fromSession(session);
    final cleanArea = isHeadquarterChannel
        ? headquarterChatAreaName
        : areaName.trim();

    if (!accountScope.isValid || cleanArea.isEmpty) {
      await stop();
      _primaryFailure = ChatFailure.invalid(
        operation: ChatOperation.bind,
        message: '회사 또는 지역 정보가 없습니다.',
      );
      notifyListeners();
      return;
    }

    if (!accountScope.canAccessChannel(
      areaName: cleanArea,
      isHeadquarterChannel: isHeadquarterChannel,
    )) {
      await stop();
      _primaryFailure = ChatFailure.invalid(
        operation: ChatOperation.bind,
        message: '현재 계정은 이 채팅 채널에 접근할 수 없습니다.',
      );
      notifyListeners();
      return;
    }

    final alreadyBound = _session?.id == session.id &&
        _division == accountScope.division &&
        _areaName == cleanArea &&
        _isHeadquarterChannel == isHeadquarterChannel &&
        _channel != null;
    if (alreadyBound && !force) return;

    await _cancelSubscriptions();
    _session = session;
    _division = accountScope.division;
    _areaName = cleanArea;
    _isHeadquarterChannel = isHeadquarterChannel;
    _channel = null;
    _latestMessages = const <ChatMessage>[];
    _olderMessages = const <ChatMessage>[];
    _messages = const <ChatMessage>[];
    _loading = true;
    _loadingOlder = false;
    _sending = false;
    _updatingPinnedNotice = false;
    _hasMore = true;
    _historyNoticeVisible = false;
    _historyGapPending = false;
    _historyGapAnchorSeq = 0;
    _resetSearchState(clearQuery: true);
    _resetSearchIndexState();
    _clearFailures();
    notifyListeners();

    try {
      final channel = _channelRepository.channelForArea(
        division: accountScope.division,
        areaName: cleanArea,
        isHeadquarter: isHeadquarterChannel,
      );
      _channel = channel;
      _channelSubscription = _channelRepository.watchChannel(channel).listen(
        (updatedChannel) {
          _channel = updatedChannel;
          if (_primaryFailure?.operation == ChatOperation.watchChannel) {
            _primaryFailure = null;
          }
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          _primaryFailure = classifyChatFailure(
            operation: ChatOperation.watchChannel,
            error: error,
            stackTrace: stackTrace,
          );
          notifyListeners();
        },
      );
      _messageSubscription = _messageRepository
          .watchLatestMessages(channel.id, limit: pageSize)
          .listen(
        (messages) {
          _applyLatestMessages(messages);
          _loading = false;
          if (_primaryFailure?.operation == ChatOperation.watchMessages ||
              _primaryFailure?.operation == ChatOperation.bind) {
            _primaryFailure = null;
          }
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          _loading = false;
          _primaryFailure = classifyChatFailure(
            operation: ChatOperation.watchMessages,
            error: error,
            stackTrace: stackTrace,
          );
          notifyListeners();
        },
      );
    } catch (error, stackTrace) {
      _loading = false;
      _primaryFailure = classifyChatFailure(
        operation: ChatOperation.bind,
        error: error,
        stackTrace: stackTrace,
      );
      notifyListeners();
    }
  }

  Future<void> retryInitialLoad() async {
    final session = _session;
    final area = _areaName;
    if (session == null || area.isEmpty) return;
    await start(
      session: session,
      areaName: area,
      isHeadquarterChannel: _isHeadquarterChannel,
      force: true,
    );
  }

  Future<bool> loadOlderMessages() async {
    final channel = _channel;
    if (channel == null ||
        _loading ||
        _loadingOlder ||
        !_hasMore ||
        _messages.isEmpty) {
      return false;
    }

    _loadingOlder = true;
    _historyFailure = null;
    notifyListeners();

    var loaded = false;
    try {
      final page = await _messageRepository.fetchOlderMessages(
        channel.id,
        beforeSeq: _messages.first.seq,
        limit: pageSize,
      );
      _olderMessages = _mergeById(page.messages, _olderMessages);
      _hasMore = page.hasMore;
      _resolveHistoryGapIfPossible();
      _rebuildMessages();
      loaded = page.messages.isNotEmpty;
    } catch (error, stackTrace) {
      _historyFailure = classifyChatFailure(
        operation: ChatOperation.loadOlder,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _loadingOlder = false;
      notifyListeners();
    }
    return loaded;
  }

  void dismissHistoryRebasedNotice() {
    if (!_historyNoticeVisible) return;
    _historyNoticeVisible = false;
    notifyListeners();
  }

  void setSearchQuery(String value) {
    final clean = value.trim();
    if (_searchQuery == clean) return;
    _searchQuery = clean;
    _resetGlobalSearchState();
    notifyListeners();
  }

  void clearSearch() {
    if (_searchQuery.isEmpty && !_globalSearchActive) return;
    _searchQuery = '';
    _resetGlobalSearchState();
    notifyListeners();
  }

  Future<bool> searchAllMessages() async {
    final channel = _channel;
    final query = _searchQuery.trim();
    if (channel == null || _searchingAll) return false;
    if (chatServerSearchToken(query).isEmpty) {
      _searchFailure = ChatFailure.invalid(
        operation: ChatOperation.searchMessages,
        message: '전체 검색어는 두 글자 이상 입력해 주세요.',
      );
      notifyListeners();
      return false;
    }

    _globalSearchActive = true;
    _globalSearchResults = const <ChatMessage>[];
    _globalSearchNextBeforeSeq = null;
    _globalSearchHasMore = false;
    _globalSearchScannedCount = 0;
    _searchFailure = null;
    return _loadGlobalSearchPage(reset: true);
  }

  Future<bool> loadMoreGlobalSearchResults() async {
    if (!_globalSearchActive ||
        !_globalSearchHasMore ||
        _searchingAll) {
      return false;
    }
    return _loadGlobalSearchPage(reset: false);
  }

  void useLocalSearch() {
    if (!_globalSearchActive) return;
    _resetGlobalSearchState();
    notifyListeners();
  }

  Future<bool> indexNextSearchHistoryBatch() async {
    final channel = _channel;
    if (channel == null ||
        _indexingSearchHistory ||
        !_searchIndexHasMore) {
      return false;
    }

    _indexingSearchHistory = true;
    _searchIndexFailure = null;
    notifyListeners();

    var completed = false;
    try {
      final batch = await _messageRepository.indexSearchHistory(
        channel.id,
        beforeSeq: _searchIndexNextBeforeSeq,
        limit: searchIndexBatchSize,
      );
      _searchIndexNextBeforeSeq = batch.nextBeforeSeq;
      _searchIndexHasMore = batch.hasMore;
      _searchIndexScannedCount += batch.scannedCount;
      _searchIndexUpdatedCount += batch.updatedCount;
      completed = true;
    } catch (error, stackTrace) {
      _searchIndexFailure = classifyChatFailure(
        operation: ChatOperation.indexSearchHistory,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _indexingSearchHistory = false;
      notifyListeners();
    }
    return completed;
  }

  Future<bool> sendText(String text) async {
    final clean = text.trim();
    final session = _session;
    final channel = _channel;
    if (clean.isEmpty || session == null || channel == null || _sending) {
      return false;
    }

    _sending = true;
    _sendFailure = null;
    notifyListeners();

    var sent = false;
    try {
      await _messageRepository.sendMessage(
        channel: channel,
        session: session,
        text: clean,
      );
      sent = true;
    } catch (error, stackTrace) {
      _sendFailure = classifyChatFailure(
        operation: ChatOperation.sendMessage,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _sending = false;
      notifyListeners();
    }
    return sent;
  }

  Future<bool> pinMessage(ChatMessage message) async {
    final session = _session;
    final channel = _channel;
    if (session == null || channel == null || _updatingPinnedNotice) {
      return false;
    }

    _updatingPinnedNotice = true;
    _noticeFailure = null;
    notifyListeners();

    var completed = false;
    try {
      await _channelRepository.pinNotice(
        channel: channel,
        message: message,
        session: session,
      );
      completed = true;
    } catch (error, stackTrace) {
      _noticeFailure = classifyChatFailure(
        operation: ChatOperation.pinNotice,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _updatingPinnedNotice = false;
      notifyListeners();
    }
    return completed;
  }

  Future<bool> clearPinnedNotice() async {
    final channel = _channel;
    final session = _session;
    if (channel == null || session == null || _updatingPinnedNotice) {
      return false;
    }

    _updatingPinnedNotice = true;
    _noticeFailure = null;
    notifyListeners();

    var completed = false;
    try {
      await _channelRepository.clearPinnedNotice(
        channel: channel,
        session: session,
      );
      completed = true;
    } catch (error, stackTrace) {
      _noticeFailure = classifyChatFailure(
        operation: ChatOperation.clearPinnedNotice,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _updatingPinnedNotice = false;
      notifyListeners();
    }
    return completed;
  }

  void clearTransientFailure(ChatOperation operation) {
    switch (operation) {
      case ChatOperation.loadOlder:
        _historyFailure = null;
        break;
      case ChatOperation.sendMessage:
        _sendFailure = null;
        break;
      case ChatOperation.pinNotice:
      case ChatOperation.clearPinnedNotice:
        _noticeFailure = null;
        break;
      case ChatOperation.searchMessages:
        _searchFailure = null;
        break;
      case ChatOperation.indexSearchHistory:
        _searchIndexFailure = null;
        break;
      case ChatOperation.bind:
      case ChatOperation.watchChannel:
      case ChatOperation.watchMessages:
      case ChatOperation.watchInbox:
        _primaryFailure = null;
        break;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _cancelSubscriptions();
    _session = null;
    _channel = null;
    _areaName = '';
    _division = '';
    _isHeadquarterChannel = false;
    _latestMessages = const <ChatMessage>[];
    _olderMessages = const <ChatMessage>[];
    _messages = const <ChatMessage>[];
    _loading = false;
    _loadingOlder = false;
    _sending = false;
    _updatingPinnedNotice = false;
    _hasMore = true;
    _historyNoticeVisible = false;
    _historyGapPending = false;
    _historyGapAnchorSeq = 0;
    _resetSearchState(clearQuery: true);
    _resetSearchIndexState();
    _clearFailures();
    notifyListeners();
  }

  Future<bool> _loadGlobalSearchPage({required bool reset}) async {
    final channel = _channel;
    final query = _searchQuery.trim();
    if (channel == null || query.isEmpty || _searchingAll) return false;

    _searchingAll = true;
    _searchFailure = null;
    final requestedQuery = query;
    notifyListeners();

    var loaded = false;
    try {
      final page = await _messageRepository.searchMessages(
        channel.id,
        query: requestedQuery,
        beforeSeq: reset ? null : _globalSearchNextBeforeSeq,
        limit: pageSize,
      );
      if (_searchQuery.trim() != requestedQuery) return false;
      _globalSearchResults = reset
          ? _mergeById(const <ChatMessage>[], page.messages)
          : _mergeById(_globalSearchResults, page.messages);
      _globalSearchNextBeforeSeq = page.nextBeforeSeq;
      _globalSearchHasMore = page.hasMore;
      _globalSearchScannedCount += page.scannedCount;
      loaded = page.messages.isNotEmpty;
    } catch (error, stackTrace) {
      if (_searchQuery.trim() == requestedQuery) {
        _searchFailure = classifyChatFailure(
          operation: ChatOperation.searchMessages,
          error: error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (_searchQuery.trim() == requestedQuery) {
        _searchingAll = false;
        notifyListeners();
      }
    }
    return loaded;
  }

  void _applyLatestMessages(List<ChatMessage> nextMessages) {
    final previousLatest = _latestMessages;
    final hasOverlap = _hasMessageOverlap(previousLatest, nextMessages);
    final previousLastSeq =
        previousLatest.isEmpty ? 0 : previousLatest.last.seq;
    final nextFirstSeq = nextMessages.isEmpty ? 0 : nextMessages.first.seq;
    final disconnectedGap = previousLatest.isNotEmpty &&
        nextMessages.isNotEmpty &&
        !hasOverlap &&
        nextFirstSeq > previousLastSeq + 1;

    if (disconnectedGap) {
      _olderMessages = const <ChatMessage>[];
      _historyGapAnchorSeq = previousLastSeq;
      _historyGapPending = true;
      _historyNoticeVisible = true;
      _hasMore = nextFirstSeq > 1;
    } else if (previousLatest.isNotEmpty) {
      _olderMessages = _mergeById(_olderMessages, previousLatest);
    }

    _latestMessages = nextMessages;
    _rebuildMessages();

    if (!disconnectedGap) {
      if (_olderMessages.isEmpty && nextMessages.length < pageSize) {
        _hasMore = false;
      } else if (_messages.isNotEmpty && _messages.first.seq <= 1) {
        _hasMore = false;
      }
    }
  }

  void _resolveHistoryGapIfPossible() {
    if (!_historyGapPending) return;
    final oldestLoadedSeq = _olderMessages.isEmpty
        ? 0
        : _olderMessages.first.seq;
    final reachedAnchor = oldestLoadedSeq > 0 &&
        oldestLoadedSeq <= _historyGapAnchorSeq + 1;
    final reachedBeginning = !_hasMore;
    if (!reachedAnchor && !reachedBeginning) return;

    _historyGapPending = false;
    _historyGapAnchorSeq = 0;
  }

  bool _hasMessageOverlap(
    List<ChatMessage> previous,
    List<ChatMessage> next,
  ) {
    if (previous.isEmpty || next.isEmpty) return true;
    final previousIds = previous.map((message) => message.id).toSet();
    return next.any((message) => previousIds.contains(message.id));
  }

  Future<void> _cancelSubscriptions() async {
    await _messageSubscription?.cancel();
    await _channelSubscription?.cancel();
    _messageSubscription = null;
    _channelSubscription = null;
  }

  void _rebuildMessages() {
    _messages = _mergeById(_olderMessages, _latestMessages);
  }

  List<ChatMessage> _mergeById(
    List<ChatMessage> first,
    List<ChatMessage> second,
  ) {
    final byId = <String, ChatMessage>{};
    for (final message in first) {
      byId[message.id] = message;
    }
    for (final message in second) {
      byId[message.id] = message;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return List<ChatMessage>.unmodifiable(merged);
  }

  void _resetSearchState({required bool clearQuery}) {
    if (clearQuery) _searchQuery = '';
    _resetGlobalSearchState();
  }

  void _resetGlobalSearchState() {
    _globalSearchResults = const <ChatMessage>[];
    _globalSearchActive = false;
    _searchingAll = false;
    _globalSearchHasMore = false;
    _globalSearchNextBeforeSeq = null;
    _globalSearchScannedCount = 0;
    _searchFailure = null;
  }

  void _resetSearchIndexState() {
    _indexingSearchHistory = false;
    _searchIndexHasMore = true;
    _searchIndexNextBeforeSeq = null;
    _searchIndexScannedCount = 0;
    _searchIndexUpdatedCount = 0;
    _searchIndexFailure = null;
  }

  void _clearFailures() {
    _primaryFailure = null;
    _historyFailure = null;
    _sendFailure = null;
    _noticeFailure = null;
    _searchFailure = null;
    _searchIndexFailure = null;
  }

  @override
  void dispose() {
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
