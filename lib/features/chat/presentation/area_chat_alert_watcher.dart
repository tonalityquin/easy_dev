import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../application/area_chat_notification_gate.dart';
import '../application/chat_area_key.dart';
import '../data/local/chat_local_notification_service.dart';
import '../data/repositories/firestore_chat_message_repository.dart';
import '../domain/models/chat_message.dart';
import '../domain/repositories/chat_message_repository.dart';

class AreaChatAlertWatcher extends StatefulWidget {
  const AreaChatAlertWatcher({
    super.key,
    required this.areaNames,
    this.child,
    this.enabled = true,
  });

  final List<String> areaNames;
  final Widget? child;
  final bool enabled;

  @override
  State<AreaChatAlertWatcher> createState() => _AreaChatAlertWatcherState();
}

class _AreaChatAlertWatcherState extends State<AreaChatAlertWatcher> {
  final ChatMessageRepository _repository = FirestoreChatMessageRepository();
  final Map<String, StreamSubscription<ChatMessageChangeBatch>> _subscriptions =
      <String, StreamSubscription<ChatMessageChangeBatch>>{};
  final Set<String> _primedAreaKeys = <String>{};
  String _currentUserId = '';
  List<String> _areaKeys = const <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(ChatLocalNotificationService.instance.ensureInitialized());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextUserId = context.read<UserState>().session?.id ?? '';
    if (_currentUserId != nextUserId) {
      _currentUserId = nextUserId;
      _resetSubscriptions();
      _syncSubscriptions();
    }
  }

  @override
  void didUpdateWidget(covariant AreaChatAlertWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.areaNames.join('\u0001') != widget.areaNames.join('\u0001')) {
      _syncSubscriptions();
    }
  }

  List<String> _normalizedAreaKeys() {
    if (!widget.enabled) return const <String>[];
    return widget.areaNames
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .map(normalizeChatAreaKey)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  void _syncSubscriptions() {
    final nextAreaKeys = _normalizedAreaKeys();
    final sameLength = _areaKeys.length == nextAreaKeys.length;
    final sameValues = sameLength &&
        List<bool>.generate(_areaKeys.length, (index) => _areaKeys[index] == nextAreaKeys[index]).every((value) => value);
    if (sameValues) return;

    final nextSet = nextAreaKeys.toSet();
    final existingSet = _subscriptions.keys.toSet();

    for (final areaKey in existingSet.difference(nextSet)) {
      unawaited(_subscriptions.remove(areaKey)?.cancel() ?? Future<void>.value());
      _primedAreaKeys.remove(areaKey);
    }

    for (final areaKey in nextSet.difference(existingSet)) {
      _subscriptions[areaKey] = _repository.watchRecentChanges(areaKey, limit: 20).listen(
        (batch) => _handleBatch(areaKey, batch),
      );
    }

    _areaKeys = nextAreaKeys;
  }

  void _resetSubscriptions() {
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _primedAreaKeys.clear();
    _areaKeys = const <String>[];
  }

  Future<void> _handleBatch(
    String areaKey,
    ChatMessageChangeBatch batch,
  ) async {
    if (batch.hasPendingWrites) return;

    if (!_primedAreaKeys.contains(areaKey)) {
      _primedAreaKeys.add(areaKey);
      return;
    }

    for (final change in batch.changes) {
      if (change.type != DocumentChangeType.added) continue;
      final message = change.message;
      if (message.senderId == _currentUserId) continue;
      if (message.id.trim().isEmpty) continue;
      if (!AreaChatNotificationGate.allow(areaKey: areaKey, messageId: message.id)) {
        continue;
      }
      await _notify(message);
    }
  }

  Future<void> _notify(ChatMessage message) async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    await ChatLocalNotificationService.instance.showChatMessage(message);
  }

  @override
  void dispose() {
    _resetSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextUserId = context.watch<UserState>().session?.id ?? '';
    if (_currentUserId != nextUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _currentUserId = nextUserId;
        _resetSubscriptions();
        _syncSubscriptions();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncSubscriptions();
      });
    }
    return widget.child ?? const SizedBox.shrink();
  }
}
