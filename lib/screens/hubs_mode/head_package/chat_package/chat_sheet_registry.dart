import 'package:flutter/foundation.dart';

import '../../noti_package/shared_spreadsheet_registry.dart';

/// (호환용) 기존 ChatSheetRegistry API를 유지하되,
/// 실제 저장/선택은 공용 SharedSpreadsheetRegistry(공지/채팅 공용 키)를 사용하도록 위임.
/// - 신규 코드에서는 가급적 SharedSpreadsheetRegistry를 직접 사용 권장.
class ChatSheetRegistry {
  ChatSheetRegistry._();

  static final ChatSheetRegistry instance = ChatSheetRegistry._();

  final ValueNotifier<List<ChatSheetEntry>> entries =
  ValueNotifier<List<ChatSheetEntry>>(<ChatSheetEntry>[]);

  /// 기존 코드 호환을 위해 "선택된 spreadsheetId"를 노출
  final ValueNotifier<String?> selectedId = ValueNotifier<String?>(null);

  Future<void>? _initFuture;

  VoidCallback? _entriesListener;
  VoidCallback? _activeAliasListener;

  Future<void> ensureInitialized() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  ChatSheetEntry? get selectedEntry {
    final id = selectedId.value;
    if (id == null) return null;
    for (final e in entries.value) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> _init() async {
    await SharedSpreadsheetRegistry.ensureBootstrapped();

    void syncEntries() {
      final src = SharedSpreadsheetRegistry.entriesNotifier.value;
      entries.value = src
          .map((e) => ChatSheetEntry(alias: e.alias, id: e.spreadsheetId))
          .toList(growable: false);
    }

    void syncSelectedId() {
      final id =
      SharedSpreadsheetRegistry.activeSpreadsheetIdOf(HeadSheetFeature.chat);
      selectedId.value = (id != null && id.trim().isNotEmpty) ? id.trim() : null;
    }

    _entriesListener ??= () {
      syncEntries();
      // entries가 바뀌면 선택값도 재계산(삭제/보정 등)
      syncSelectedId();
    };

    _activeAliasListener ??= () {
      syncSelectedId();
    };

    SharedSpreadsheetRegistry.entriesNotifier.addListener(_entriesListener!);
    SharedSpreadsheetRegistry.activeChatAliasNotifier
        .addListener(_activeAliasListener!);

    // 최초 1회 동기화
    syncEntries();
    syncSelectedId();
  }

  /// 기존 시그니처 유지: spreadsheetId로 선택
  Future<void> select(String spreadsheetId) async {
    await ensureInitialized();

    final id = spreadsheetId.trim();
    if (id.isEmpty) return;

    final entry = SharedSpreadsheetRegistry.findBySpreadsheetId(id);
    if (entry == null) return;

    await SharedSpreadsheetRegistry.setActiveAlias(
        HeadSheetFeature.chat, entry.alias);
  }

  Future<void> addEntry({
    required String alias,
    required String spreadsheetId,
  }) async {
    await ensureInitialized();

    final a = alias.trim();
    final id = spreadsheetId.trim();
    if (a.isEmpty || id.isEmpty) return;

    await SharedSpreadsheetRegistry.addEntry(alias: a, spreadsheetId: id);
    await SharedSpreadsheetRegistry.setActiveAlias(HeadSheetFeature.chat, a);
  }

  Future<void> updateEntry({
    required String oldSpreadsheetId,
    required String newAlias,
    required String newSpreadsheetId,
  }) async {
    await ensureInitialized();

    final oldId = oldSpreadsheetId.trim();
    final a = newAlias.trim();
    final newId = newSpreadsheetId.trim();
    if (oldId.isEmpty || a.isEmpty || newId.isEmpty) return;

    final oldEntry = SharedSpreadsheetRegistry.findBySpreadsheetId(oldId);
    if (oldEntry == null) return;

    await SharedSpreadsheetRegistry.updateEntry(
      oldAlias: oldEntry.alias,
      newAlias: a,
      newSpreadsheetId: newId,
    );

    // 채팅 활성 별명이 기존 alias였다면 갱신
    final active = SharedSpreadsheetRegistry.activeChatAliasNotifier.value.trim();
    if (active == oldEntry.alias) {
      await SharedSpreadsheetRegistry.setActiveAlias(HeadSheetFeature.chat, a);
    }
  }

  Future<void> removeEntry(String spreadsheetId) async {
    await ensureInitialized();

    final id = spreadsheetId.trim();
    if (id.isEmpty) return;

    final entry = SharedSpreadsheetRegistry.findBySpreadsheetId(id);
    if (entry == null) return;

    // ✅ FIX: removeEntry는 포지셔널 인자 1개를 받음
    await SharedSpreadsheetRegistry.removeEntry(entry.alias);

    // 선택값 보정은 SharedSpreadsheetRegistry 내부 로직에서 처리되도록 설계(권장)
  }
}

@immutable
class ChatSheetEntry {
  final String alias;
  final String id;

  const ChatSheetEntry({
    required this.alias,
    required this.id,
  });
}
