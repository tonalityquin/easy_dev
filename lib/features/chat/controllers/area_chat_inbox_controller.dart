import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/area_chat_notification_gate.dart';
import '../application/area_chat_read_receipts.dart';
import '../application/chat_area_key.dart';
import '../application/chat_failure.dart';
import '../data/local/chat_local_notification_service.dart';
import '../data/repositories/firestore_chat_channel_repository.dart';
import '../domain/models/chat_channel.dart';
import '../domain/repositories/chat_channel_repository.dart';

class AreaChatInboxSnapshot {
  const AreaChatInboxSnapshot({
    required this.division,
    required this.selectedArea,
    required this.isHeadquarterAccount,
    required this.channelsByChannelId,
    required this.readSeqByChannelId,
    required this.failure,
  });

  final String division;
  final String selectedArea;
  final bool isHeadquarterAccount;
  final Map<String, ChatChannel> channelsByChannelId;
  final Map<String, int> readSeqByChannelId;
  final ChatFailure? failure;

  String _channelIdForArea(String areaName) {
    final cleanArea = areaName.trim();
    if (cleanArea.isEmpty || division.isEmpty) return '';
    final isHeadquarterChannel = isHeadquarterChatAreaName(cleanArea) ||
        isHeadquarterAccount && sameChatIdentity(cleanArea, division);
    return buildChatChannelId(
      division: division,
      areaName: isHeadquarterChannel ? headquarterChatAreaName : cleanArea,
      isHeadquarter: isHeadquarterChannel,
    );
  }

  ChatChannel? channelForArea(String areaName) {
    final channelId = _channelIdForArea(areaName);
    if (channelId.isEmpty) return null;
    return channelsByChannelId[channelId];
  }

  int unreadCountForArea(String areaName, String currentUserId) {
    final channelId = _channelIdForArea(areaName);
    if (channelId.isEmpty) return 0;
    final channel = channelsByChannelId[channelId];
    if (channel == null || !channel.hasMessage) return 0;
    final readSeq = readSeqByChannelId[channelId] ?? 0;
    final raw = math.max(0, channel.messageSeq - readSeq);
    if (raw <= 0) return 0;
    if (raw == 1 && channel.lastSenderId == currentUserId) return 0;
    return raw;
  }

  bool hasUnreadForArea(String areaName, String currentUserId) {
    return unreadCountForArea(areaName, currentUserId) > 0;
  }
}

class AreaChatInboxController extends ChangeNotifier {
  AreaChatInboxController({ChatChannelRepository? channelRepository})
      : _channelRepository =
            channelRepository ?? FirestoreChatChannelRepository();

  final ChatChannelRepository _channelRepository;
  final Map<String, ChatChannel> _channelsByChannelId =
      <String, ChatChannel>{};
  final Map<String, int> _readSeqByChannelId = <String, int>{};
  final Map<String, String> _lastMessageIdByChannelId = <String, String>{};
  final Map<String, StreamSubscription<ChatChannelChangeBatch>> _subscriptions =
      <String, StreamSubscription<ChatChannelChangeBatch>>{};
  final Set<String> _primedSubscriptionKeys = <String>{};
  StreamSubscription<AreaChatReadReceiptEvent>? _receiptSub;
  List<String> _channelIds = const <String>[];
  String _currentUserId = '';
  String _division = '';
  String _selectedArea = '';
  bool _isHeadquarterAccount = false;
  bool _notificationsEnabled = true;
  Set<String> _suppressedChannelIds = const <String>{};
  ChatFailure? _failure;
  bool _disposed = false;
  int _readLoadGeneration = 0;

  AreaChatInboxSnapshot get snapshot => AreaChatInboxSnapshot(
        division: _division,
        selectedArea: _selectedArea,
        isHeadquarterAccount: _isHeadquarterAccount,
        channelsByChannelId:
            Map<String, ChatChannel>.unmodifiable(_channelsByChannelId),
        readSeqByChannelId:
            Map<String, int>.unmodifiable(_readSeqByChannelId),
        failure: _failure,
      );

  void configure({
    required String division,
    required String selectedArea,
    required List<String> areaNames,
    required String currentUserId,
    bool notificationsEnabled = true,
    List<String> suppressedAreaNames = const <String>[],
  }) {
    if (_disposed) return;

    final nextDivision = division.trim();
    final nextSelectedArea = selectedArea.trim();
    final nextUserId = currentUserId.trim();
    final nextIsHeadquarter =
        sameChatIdentity(nextDivision, nextSelectedArea);
    final nextChannelIds = nextUserId.isEmpty
        ? const <String>[]
        : _resolveChannelIds(
            division: nextDivision,
            selectedArea: nextSelectedArea,
            isHeadquarterAccount: nextIsHeadquarter,
            areaNames: areaNames,
          );
    final nextSuppressedChannelIds = nextUserId.isEmpty
        ? const <String>{}
        : _resolveChannelIds(
            division: nextDivision,
            selectedArea: nextSelectedArea,
            isHeadquarterAccount: nextIsHeadquarter,
            areaNames: suppressedAreaNames,
          ).toSet();

    final scopeChanged = _division != nextDivision ||
        _selectedArea != nextSelectedArea ||
        _isHeadquarterAccount != nextIsHeadquarter;
    final userChanged = _currentUserId != nextUserId;
    final channelsChanged = !_sameStringList(_channelIds, nextChannelIds);

    _division = nextDivision;
    _selectedArea = nextSelectedArea;
    _isHeadquarterAccount = nextIsHeadquarter;
    _currentUserId = nextUserId;
    _notificationsEnabled = notificationsEnabled;
    _suppressedChannelIds = nextSuppressedChannelIds;

    if (!scopeChanged && !userChanged && !channelsChanged) return;

    _channelIds = nextChannelIds;
    if (scopeChanged || channelsChanged) {
      _syncSubscriptions();
    }
    unawaited(_loadReadSeqs(nextChannelIds, nextUserId));
  }

  List<String> _resolveChannelIds({
    required String division,
    required String selectedArea,
    required bool isHeadquarterAccount,
    required List<String> areaNames,
  }) {
    if (division.isEmpty || selectedArea.isEmpty) {
      return const <String>[];
    }

    if (areaNames.isEmpty) return const <String>[];

    final requestedAreas = isHeadquarterAccount
        ? areaNames
        : areaNames.where(
            (area) => sameChatIdentity(area, selectedArea),
          );
    final ids = <String>{};

    for (final rawArea in requestedAreas) {
      final area = rawArea.trim();
      if (area.isEmpty) continue;
      final isHeadquarterChannel = isHeadquarterChatAreaName(area) ||
          isHeadquarterAccount && sameChatIdentity(area, division);
      if (isHeadquarterChannel && !isHeadquarterAccount) continue;
      if (!isHeadquarterAccount && !sameChatIdentity(area, selectedArea)) {
        continue;
      }
      final channelId = buildChatChannelId(
        division: division,
        areaName:
            isHeadquarterChannel ? headquarterChatAreaName : area,
        isHeadquarter: isHeadquarterChannel,
      );
      if (channelId.isNotEmpty) ids.add(channelId);
    }

    final result = ids.toList(growable: false)..sort();
    return result;
  }

  Future<void> _loadReadSeqs(
    List<String> channelIds,
    String currentUserId,
  ) async {
    final generation = ++_readLoadGeneration;
    final next = <String, int>{};
    for (final channelId in channelIds) {
      next[channelId] = await AreaChatReadReceipts.readSeq(
        channelId,
        userId: currentUserId,
      );
    }
    if (_disposed || generation != _readLoadGeneration) return;
    _readSeqByChannelId
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void startReadReceiptStream() {
    _receiptSub ??= AreaChatReadReceipts.stream.listen((event) {
      if (_disposed || event.userId != _currentUserId) return;
      if (!_channelIds.contains(event.channelId)) return;
      _readSeqByChannelId[event.channelId] = event.readSeq;
      notifyListeners();
    });
    unawaited(ChatLocalNotificationService.instance.ensureInitialized());
  }

  void _syncSubscriptions() {
    final chunks = _chunkChannelIds(_channelIds, 10);
    final nextKeys = chunks.map((chunk) => chunk.join('\u0001')).toSet();
    final currentKeys = _subscriptions.keys.toSet();

    for (final key in currentKeys.difference(nextKeys)) {
      unawaited(_subscriptions.remove(key)?.cancel() ?? Future<void>.value());
      _primedSubscriptionKeys.remove(key);
    }

    for (final chunk in chunks) {
      final subscriptionKey = chunk.join('\u0001');
      if (_subscriptions.containsKey(subscriptionKey)) continue;
      _subscriptions[subscriptionKey] = _channelRepository
          .watchChannelBatchByChannelIds(chunk)
          .listen(
            (batch) => _handleBatch(subscriptionKey, chunk, batch),
            onError: (Object error, StackTrace stackTrace) {
              if (_disposed) return;
              _failure = classifyChatFailure(
                operation: ChatOperation.watchInbox,
                error: error,
                stackTrace: stackTrace,
              );
              notifyListeners();
            },
          );
    }

    final activeSet = _channelIds.toSet();
    _channelsByChannelId.removeWhere((key, _) => !activeSet.contains(key));
    _lastMessageIdByChannelId
        .removeWhere((key, _) => !activeSet.contains(key));
    _readSeqByChannelId.removeWhere((key, _) => !activeSet.contains(key));
    notifyListeners();
  }

  Future<void> _handleBatch(
    String subscriptionKey,
    List<String> chunkChannelIds,
    ChatChannelChangeBatch batch,
  ) async {
    if (_disposed) return;

    final changedChannels = <ChatChannel>[];
    final returnedChannelIds = <String>{};
    final isPrimed = _primedSubscriptionKeys.contains(subscriptionKey);
    _failure = null;

    for (final channel in batch.channels) {
      final channelId = channel.id.trim();
      if (channelId.isEmpty || !_canReceive(channel)) continue;
      returnedChannelIds.add(channelId);
      final previousLastMessageId =
          _lastMessageIdByChannelId[channelId] ?? '';
      _channelsByChannelId[channelId] = channel;
      _lastMessageIdByChannelId[channelId] = channel.lastMessageId;
      if (isPrimed &&
          !batch.hasPendingWrites &&
          channel.hasMessage &&
          previousLastMessageId != channel.lastMessageId) {
        changedChannels.add(channel);
      }
    }

    for (final channelId in chunkChannelIds) {
      if (!returnedChannelIds.contains(channelId)) {
        _channelsByChannelId.remove(channelId);
        _lastMessageIdByChannelId.remove(channelId);
      }
    }

    if (!isPrimed) {
      _primedSubscriptionKeys.add(subscriptionKey);
    }

    notifyListeners();

    if (!_notificationsEnabled) return;
    for (final channel in changedChannels) {
      await _maybeNotify(channel);
    }
  }

  bool _canReceive(ChatChannel channel) {
    if (!_channelIds.contains(channel.id)) return false;
    if (channel.division != _division) return false;
    if (channel.companyKey != normalizeChatCompanyKey(_division)) return false;
    final expectedChannelId = buildChatChannelId(
      division: _division,
      areaName: channel.isHeadquarter
          ? headquarterChatAreaName
          : channel.areaName,
      isHeadquarter: channel.isHeadquarter,
    );
    if (expectedChannelId != channel.id) return false;
    if (channel.isHeadquarter) return _isHeadquarterAccount;
    if (_isHeadquarterAccount) return true;
    return sameChatIdentity(channel.areaName, _selectedArea);
  }

  Future<void> _maybeNotify(ChatChannel channel) async {
    if (!_canReceive(channel)) return;
    final channelId = channel.id.trim();
    final messageId = channel.lastMessageId.trim();
    if (channelId.isEmpty || messageId.isEmpty) return;
    if (_suppressedChannelIds.contains(channelId)) return;
    if (channel.lastSenderId == _currentUserId) return;
    final readSeq = _readSeqByChannelId[channelId] ?? 0;
    if (channel.messageSeq <= readSeq) return;
    if (!AreaChatNotificationGate.allow(
      channelId: channelId,
      messageId: messageId,
    )) {
      return;
    }
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    await ChatLocalNotificationService.instance.showChatChannelSummary(channel);
  }

  List<List<String>> _chunkChannelIds(List<String> channelIds, int size) {
    if (channelIds.isEmpty) return const <List<String>>[];
    final chunks = <List<String>>[];
    for (var i = 0; i < channelIds.length; i += size) {
      final end = math.min(i + size, channelIds.length);
      chunks.add(channelIds.sublist(i, end));
    }
    return chunks;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_receiptSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
