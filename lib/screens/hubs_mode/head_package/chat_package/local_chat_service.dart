import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/sheet_chat_service.dart';

/// ✅ Sheets API 없이 동작하는 로컬 채팅 서비스
/// - SharedPreferences에 메시지를 저장/로드
/// - UI는 SheetChatState/SheetChatMessage 타입을 그대로 사용하여 ChatPanel 변경 최소화
class LocalChatService {
  LocalChatService._();

  static final LocalChatService instance = LocalChatService._();

  final ValueNotifier<SheetChatState> state =
  ValueNotifier<SheetChatState>(SheetChatState.empty);

  static const int maxMessagesInUi = SheetChatService.maxMessagesInUi;

  String _scopeKey = '';

  String _messagesPrefsKey(String scopeKey) => 'chat_local_messages_v1_$scopeKey';

  Future<void> start(String scopeKey, {bool force = false}) async {
    final key = scopeKey.trim();
    final sameScope = _scopeKey == key;
    _scopeKey = key;

    if (sameScope && !force && state.value.messages.isNotEmpty) return;

    state.value = state.value.copyWith(loading: true, error: null);

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_messagesPrefsKey(_scopeKey)) ?? '';
      final msgs = _decode(raw);

      final trimmed = msgs.length <= maxMessagesInUi
          ? msgs
          : msgs.sublist(msgs.length - maxMessagesInUi);

      state.value = SheetChatState(loading: false, error: null, messages: trimmed);
    } catch (e) {
      state.value = state.value.copyWith(
        loading: false,
        error: '로컬 채팅 로드 실패: $e',
        messages: const [],
      );
    }
  }

  Future<void> refresh() async {
    await start(_scopeKey, force: true);
  }

  Future<void> sendMessage(String message) async {
    final msg = message.trim();
    if (msg.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _messagesPrefsKey(_scopeKey);

      final raw = prefs.getString(key) ?? '';
      final list = _decode(raw);

      final now = DateTime.now().toUtc();
      list.add(SheetChatMessage(time: now, text: msg));

      final trimmed = list.length <= maxMessagesInUi
          ? list
          : list.sublist(list.length - maxMessagesInUi);

      await prefs.setString(key, _encode(trimmed));

      state.value = SheetChatState(loading: false, error: null, messages: trimmed);
    } catch (e) {
      state.value = state.value.copyWith(
        loading: false,
        error: '로컬 채팅 전송 실패: $e',
      );
    }
  }

  List<SheetChatMessage> _decode(String raw) {
    if (raw.trim().isEmpty) return <SheetChatMessage>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SheetChatMessage>[];

      final out = <SheetChatMessage>[];
      for (final it in decoded) {
        if (it is! Map) continue;
        final tRaw = (it['t'] ?? '').toString().trim();
        final mRaw = (it['m'] ?? '').toString().trim();
        if (mRaw.isEmpty) continue;

        DateTime? t;
        if (tRaw.isNotEmpty) t = DateTime.tryParse(tRaw);

        out.add(SheetChatMessage(time: t, text: mRaw));
      }
      return out;
    } catch (_) {
      return <SheetChatMessage>[];
    }
  }

  String _encode(List<SheetChatMessage> msgs) {
    final list = msgs
        .map((m) => {
      't': m.time?.toUtc().toIso8601String() ?? '',
      'm': m.text,
    })
        .toList(growable: false);

    return jsonEncode(list);
  }
}
