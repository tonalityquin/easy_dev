import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/area_chat_notification_gate.dart';
import '../application/area_chat_read_receipts.dart';
import '../application/chat_area_key.dart';
import '../data/local/chat_local_notification_service.dart';
import '../data/repositories/firestore_chat_channel_repository.dart';
import '../domain/models/chat_channel.dart';
import '../domain/repositories/chat_channel_repository.dart';

class AreaChatInboxSnapshot {
  const AreaChatInboxSnapshot({
    required this.channelsByAreaKey,
    required this.readSeqByAreaKey,
  });

  final Map<String, ChatChannel> channelsByAreaKey;
  final Map<String, int> readSeqByAreaKey;

  ChatChannel? channelForArea(String areaName) {
    return channelsByAreaKey[normalizeChatAreaKey(areaName)];
  }

  int unreadCountForArea(String areaName, String currentUserId) {
    final areaKey = normalizeChatAreaKey(areaName);
    final channel = channelsByAreaKey[areaKey];
    if (channel == null || !channel.hasMessage) return 0;
    final readSeq = readSeqByAreaKey[areaKey] ?? 0;
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
  final Map<String, ChatChannel> _channelsByAreaKey = <String, ChatChannel>{};
  final Map<String, int> _readSeqByAreaKey = <String, int>{};
  final Map<String, String> _lastMessageIdByAreaKey = <String, String>{};
  final Map<String, StreamSubscription<ChatChannelChangeBatch>> _subscriptions =
      <String, StreamSubscription<ChatChannelChangeBatch>>{};
  final Set<String> _primedSubscriptionKeys = <String>{};
  StreamSubscription<AreaChatReadReceiptEvent>? _receiptSub;
  List<String> _areaKeys = const <String>[];
  String _currentUserId = '';
  bool _notificationsEnabled = true;
  Set<String> _suppressedAreaKeys = const <String>{};
  bool _disposed = false;

  AreaChatInboxSnapshot get snapshot => AreaChatInboxSnapshot(
        channelsByAreaKey: Map<String, ChatChannel>.unmodifiable(_channelsByAreaKey),
        readSeqByAreaKey: Map<String, int>.unmodifiable(_readSeqByAreaKey),
      );

  void configure({
    required List<String> areaNames,
    required String currentUserId,
    bool notificationsEnabled = true,
    Set<String> suppressedAreaKeys = const <String>{},
  }) {
    if (_disposed) return;
    _currentUserId = currentUserId;
    _notificationsEnabled = notificationsEnabled;
    _suppressedAreaKeys = suppressedAreaKeys
        .map((areaKey) => areaKey.trim())
        .where((areaKey) => areaKey.isNotEmpty)
        .toSet();

    final nextAreaKeys = areaNames
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .map(normalizeChatAreaKey)
        .toSet()
        .toList(growable: false)
      ..sort();

    if (_sameStringList(_areaKeys, nextAreaKeys)) {
      return;
    }

    _areaKeys = nextAreaKeys;
    _syncSubscriptions();
    unawaited(_loadReadSeqs(nextAreaKeys));
  }

  Future<void> _loadReadSeqs(List<String> areaKeys) async {
    final next = <String, int>{};
    for (final areaKey in areaKeys) {
      next[areaKey] = await AreaChatReadReceipts.readSeq(areaKey);
    }
    if (_disposed) return;
    _readSeqByAreaKey
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void startReadReceiptStream() {
    _receiptSub ??= AreaChatReadReceipts.stream.listen((event) {
      if (_disposed) return;
      _readSeqByAreaKey[event.areaKey] = event.readSeq;
      notifyListeners();
    });
    unawaited(ChatLocalNotificationService.instance.ensureInitialized());
  }

  void _syncSubscriptions() {
    final chunks = _chunkAreaKeys(_areaKeys, 10);
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
          .watchChannelBatchByAreaKeys(chunk)
          .listen(
            (batch) => _handleBatch(subscriptionKey, chunk, batch),
            onError: (_) {},
          );
    }

    final activeSet = _areaKeys.toSet();
    _channelsByAreaKey.removeWhere((key, _) => !activeSet.contains(key));
    _lastMessageIdByAreaKey.removeWhere((key, _) => !activeSet.contains(key));
    notifyListeners();
  }

  Future<void> _handleBatch(
    String subscriptionKey,
    List<String> chunkAreaKeys,
    ChatChannelChangeBatch batch,
  ) async {
    if (_disposed) return;

    final changedChannels = <ChatChannel>[];
    final returnedAreaKeys = <String>{};
    final isPrimed = _primedSubscriptionKeys.contains(subscriptionKey);

    for (final channel in batch.channels) {
      final areaKey = channel.areaKey.trim();
      if (areaKey.isEmpty) continue;
      returnedAreaKeys.add(areaKey);
      final previousLastMessageId = _lastMessageIdByAreaKey[areaKey] ?? '';
      _channelsByAreaKey[areaKey] = channel;
      _lastMessageIdByAreaKey[areaKey] = channel.lastMessageId;
      if (isPrimed &&
          !batch.hasPendingWrites &&
          channel.hasMessage &&
          previousLastMessageId != channel.lastMessageId) {
        changedChannels.add(channel);
      }
    }

    for (final areaKey in chunkAreaKeys) {
      if (!returnedAreaKeys.contains(areaKey)) {
        _channelsByAreaKey.remove(areaKey);
        _lastMessageIdByAreaKey.remove(areaKey);
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

  Future<void> _maybeNotify(ChatChannel channel) async {
    final areaKey = channel.areaKey.trim();
    final messageId = channel.lastMessageId.trim();
    if (areaKey.isEmpty || messageId.isEmpty) return;
    if (_suppressedAreaKeys.contains(areaKey)) return;
    if (channel.lastSenderId == _currentUserId) return;
    final readSeq = _readSeqByAreaKey[areaKey] ?? 0;
    if (channel.messageSeq <= readSeq) return;
    if (!AreaChatNotificationGate.allow(areaKey: areaKey, messageId: messageId)) {
      return;
    }
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    await ChatLocalNotificationService.instance.showChatChannelSummary(channel);
  }

  List<List<String>> _chunkAreaKeys(List<String> areaKeys, int size) {
    if (areaKeys.isEmpty) return const <List<String>>[];
    final chunks = <List<String>>[];
    for (var i = 0; i < areaKeys.length; i += size) {
      final end = math.min(i + size, areaKeys.length);
      chunks.add(areaKeys.sublist(i, end));
    }
    return chunks;
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
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
