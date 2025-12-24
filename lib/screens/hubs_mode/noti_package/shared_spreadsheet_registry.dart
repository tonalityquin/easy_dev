import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/api/sheets_config.dart';

/// 공지/채팅이 "공유"하는 스프레드시트 레지스트리 키
/// - 채팅도 반드시 이 키를 사용하도록 리팩터링해야 "공유"가 됩니다.
const String kHeadSpreadsheetAliasRegistryKey = 'head_spreadsheet_alias_registry_v1';

/// 기능별 "활성 별명" 저장 키 (선택값은 기능별로 유지)
const String kHeadActiveSheetAliasNoticeKey = 'head_active_sheet_alias_notice_v1';
const String kHeadActiveSheetAliasChatKey = 'head_active_sheet_alias_chat_v1';

/// (레거시) 공지 단일 ID 키 — 1회 마이그레이션 용도
const String _legacyNoticeSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

enum HeadSheetFeature { notice, chat }

class SheetAliasEntry {
  final String alias;
  final String spreadsheetId;
  final int updatedAtMs;

  const SheetAliasEntry({
    required this.alias,
    required this.spreadsheetId,
    required this.updatedAtMs,
  });

  SheetAliasEntry copyWith({
    String? alias,
    String? spreadsheetId,
    int? updatedAtMs,
  }) {
    return SheetAliasEntry(
      alias: alias ?? this.alias,
      spreadsheetId: spreadsheetId ?? this.spreadsheetId,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'id': spreadsheetId,
    't': updatedAtMs,
  };

  static SheetAliasEntry? fromJson(dynamic v) {
    if (v is! Map) return null;
    final alias = (v['alias'] ?? '').toString().trim();
    final id = (v['id'] ?? '').toString().trim();
    final tRaw = v['t'];
    final t = (tRaw is int) ? tRaw : int.tryParse((tRaw ?? '').toString()) ?? 0;
    if (alias.isEmpty || id.isEmpty) return null;
    return SheetAliasEntry(alias: alias, spreadsheetId: id, updatedAtMs: t);
  }
}

/// 공지/채팅이 공유하는 스프레드시트 레지스트리
class SharedSpreadsheetRegistry {
  SharedSpreadsheetRegistry._();

  static bool _bootstrapped = false;
  static SharedPreferences? _prefs;

  /// 레지스트리(별명+ID 목록)
  static final ValueNotifier<List<SheetAliasEntry>> entriesNotifier =
  ValueNotifier<List<SheetAliasEntry>>(<SheetAliasEntry>[]);

  /// 기능별 활성 별명
  static final ValueNotifier<String> activeNoticeAliasNotifier = ValueNotifier<String>('');
  static final ValueNotifier<String> activeChatAliasNotifier = ValueNotifier<String>('');

  /// 공지 내용 저장/변경 트리거(예: Header가 listen해서 reload)
  static final ValueNotifier<int> noticeRevisionNotifier = ValueNotifier<int>(0);

  static Future<void> ensureBootstrapped() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    _prefs ??= await SharedPreferences.getInstance();

    await _loadRegistry();
    await _loadActives();
    await _migrateLegacyNoticeIfNeeded();

    // 활성 별명이 없는데 레지스트리가 있으면 첫 항목으로 자동 지정(공지/채팅 각각)
    await _ensureActiveAliasExists(HeadSheetFeature.notice);
    await _ensureActiveAliasExists(HeadSheetFeature.chat);
  }

  static Future<void> reload() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _loadRegistry();
    await _loadActives();
    await _ensureActiveAliasExists(HeadSheetFeature.notice);
    await _ensureActiveAliasExists(HeadSheetFeature.chat);
  }

  static List<SheetAliasEntry> get entries => entriesNotifier.value;

  static String activeAliasOf(HeadSheetFeature feature) {
    switch (feature) {
      case HeadSheetFeature.notice:
        return activeNoticeAliasNotifier.value.trim();
      case HeadSheetFeature.chat:
        return activeChatAliasNotifier.value.trim();
    }
  }

  static String? spreadsheetIdOfAlias(String alias) {
    final a = alias.trim();
    if (a.isEmpty) return null;
    for (final e in entriesNotifier.value) {
      if (e.alias == a) return e.spreadsheetId;
    }
    return null;
  }

  static String? activeSpreadsheetIdOf(HeadSheetFeature feature) {
    final a = activeAliasOf(feature);
    if (a.isEmpty) return null;
    return spreadsheetIdOfAlias(a);
  }

  static bool isLikelyAlias(String alias) => alias.trim().length >= 1;

  static bool isLikelySpreadsheetIdOrUrl(String raw) => raw.trim().length >= 10;

  static String normalizeSpreadsheetId(String rawOrUrl) {
    final raw = rawOrUrl.trim();
    if (raw.isEmpty) return '';
    return SheetsConfig.extractSpreadsheetId(raw).trim();
  }

  /// 추가/수정(별명 기준 upsert)
  static Future<void> upsert({
    required String alias,
    required String rawIdOrUrl,
    bool setActiveForNotice = false,
    bool setActiveForChat = false,
  }) async {
    await ensureBootstrapped();

    final a = alias.trim();
    final id = normalizeSpreadsheetId(rawIdOrUrl);

    if (!isLikelyAlias(a)) {
      throw ArgumentError('alias is invalid');
    }
    if (id.isEmpty) {
      throw ArgumentError('spreadsheet id is invalid');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final list = List<SheetAliasEntry>.from(entriesNotifier.value);

    final idx = list.indexWhere((e) => e.alias == a);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(spreadsheetId: id, updatedAtMs: now);
    } else {
      list.add(SheetAliasEntry(alias: a, spreadsheetId: id, updatedAtMs: now));
    }

    // 정렬: 최근 수정 우선
    list.sort((x, y) => y.updatedAtMs.compareTo(x.updatedAtMs));

    await _persistRegistry(list);

    if (setActiveForNotice) {
      await setActiveAlias(HeadSheetFeature.notice, a);
    }
    if (setActiveForChat) {
      await setActiveAlias(HeadSheetFeature.chat, a);
    }
  }

  static Future<void> removeAlias(String alias) async {
    await ensureBootstrapped();
    final a = alias.trim();
    final list = entriesNotifier.value.where((e) => e.alias != a).toList();

    await _persistRegistry(list);

    // 활성 별명이 삭제되면 기능별로 재설정
    if (activeNoticeAliasNotifier.value.trim() == a) {
      await _ensureActiveAliasExists(HeadSheetFeature.notice);
    }
    if (activeChatAliasNotifier.value.trim() == a) {
      await _ensureActiveAliasExists(HeadSheetFeature.chat);
    }
  }

  static Future<void> renameAlias({
    required String oldAlias,
    required String newAlias,
  }) async {
    await ensureBootstrapped();

    final o = oldAlias.trim();
    final n = newAlias.trim();
    if (o.isEmpty || n.isEmpty) throw ArgumentError('alias is invalid');

    final list = List<SheetAliasEntry>.from(entriesNotifier.value);
    if (list.any((e) => e.alias == n)) {
      throw ArgumentError('alias already exists');
    }

    final idx = list.indexWhere((e) => e.alias == o);
    if (idx < 0) throw ArgumentError('old alias not found');

    list[idx] = list[idx].copyWith(alias: n);

    await _persistRegistry(list);

    // 기능별 활성 별명 갱신
    if (activeNoticeAliasNotifier.value.trim() == o) {
      await setActiveAlias(HeadSheetFeature.notice, n);
    }
    if (activeChatAliasNotifier.value.trim() == o) {
      await setActiveAlias(HeadSheetFeature.chat, n);
    }
  }

  static Future<void> setActiveAlias(HeadSheetFeature feature, String alias) async {
    await ensureBootstrapped();

    final a = alias.trim();
    if (a.isEmpty) return;

    // 레지스트리에 없는 별명은 설정 불가
    if (!entriesNotifier.value.any((e) => e.alias == a)) return;

    _prefs ??= await SharedPreferences.getInstance();

    switch (feature) {
      case HeadSheetFeature.notice:
        await _prefs!.setString(kHeadActiveSheetAliasNoticeKey, a);
        activeNoticeAliasNotifier.value = a;
        break;
      case HeadSheetFeature.chat:
        await _prefs!.setString(kHeadActiveSheetAliasChatKey, a);
        activeChatAliasNotifier.value = a;
        break;
    }
  }

  static void bumpNoticeRevision() {
    noticeRevisionNotifier.value = noticeRevisionNotifier.value + 1;
  }

  // -----------------------
  // internal load/persist
  // -----------------------

  static Future<void> _loadRegistry() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = (_prefs!.getString(kHeadSpreadsheetAliasRegistryKey) ?? '').trim();
    if (raw.isEmpty) {
      entriesNotifier.value = <SheetAliasEntry>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);

      // 1) 새 포맷: { items: [...] }
      if (decoded is Map && decoded['items'] is List) {
        final items = (decoded['items'] as List)
            .map((e) => SheetAliasEntry.fromJson(e))
            .whereType<SheetAliasEntry>()
            .toList();
        items.sort((x, y) => y.updatedAtMs.compareTo(x.updatedAtMs));
        entriesNotifier.value = items;
        return;
      }

      // 2) 구 포맷: [ ... ]
      if (decoded is List) {
        final items = decoded
            .map((e) => SheetAliasEntry.fromJson(e))
            .whereType<SheetAliasEntry>()
            .toList();
        items.sort((x, y) => y.updatedAtMs.compareTo(x.updatedAtMs));
        entriesNotifier.value = items;
        return;
      }

      entriesNotifier.value = <SheetAliasEntry>[];
    } catch (_) {
      entriesNotifier.value = <SheetAliasEntry>[];
    }
  }

  static Future<void> _persistRegistry(List<SheetAliasEntry> list) async {
    _prefs ??= await SharedPreferences.getInstance();

    // 포맷: { version: 1, items: [...] }
    final payload = <String, dynamic>{
      'version': 1,
      'items': list.map((e) => e.toJson()).toList(),
    };

    await _prefs!.setString(kHeadSpreadsheetAliasRegistryKey, jsonEncode(payload));
    entriesNotifier.value = list;
  }

  static Future<void> _loadActives() async {
    _prefs ??= await SharedPreferences.getInstance();
    activeNoticeAliasNotifier.value =
        (_prefs!.getString(kHeadActiveSheetAliasNoticeKey) ?? '').trim();
    activeChatAliasNotifier.value =
        (_prefs!.getString(kHeadActiveSheetAliasChatKey) ?? '').trim();
  }

  static Future<void> _ensureActiveAliasExists(HeadSheetFeature feature) async {
    final list = entriesNotifier.value;
    if (list.isEmpty) {
      // 활성값은 비워둠
      if (feature == HeadSheetFeature.notice) activeNoticeAliasNotifier.value = '';
      if (feature == HeadSheetFeature.chat) activeChatAliasNotifier.value = '';
      return;
    }

    final active = activeAliasOf(feature);
    if (active.isNotEmpty && list.any((e) => e.alias == active)) return;

    // fallback: 첫 항목
    await setActiveAlias(feature, list.first.alias);
  }

  static Future<void> _migrateLegacyNoticeIfNeeded() async {
    _prefs ??= await SharedPreferences.getInstance();

    // 레지스트리가 비어있고, 레거시 공지 키가 있으면 마이그레이션
    if (entriesNotifier.value.isNotEmpty) return;

    final legacy = (_prefs!.getString(_legacyNoticeSpreadsheetIdKey) ?? '').trim();
    if (legacy.isEmpty) return;

    final id = normalizeSpreadsheetId(legacy);
    if (id.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final migrated = <SheetAliasEntry>[
      SheetAliasEntry(alias: '공지(기존)', spreadsheetId: id, updatedAtMs: now),
    ];

    await _persistRegistry(migrated);
    await setActiveAlias(HeadSheetFeature.notice, migrated.first.alias);

    // 레거시 키 제거(원치 않으면 제거 로직을 주석 처리)
    await _prefs!.remove(_legacyNoticeSpreadsheetIdKey);
  }

  // =======================================================================
  // ✅ 호환용 어댑터 API (기존 ChatSheetRegistry/ChatRuntime 호출부와의 연결용)
  // - 기존 답변 코드에서 사용한 메서드명을 맞춰 컴파일 에러를 제거합니다.
  // =======================================================================

  /// spreadsheetId(또는 URL)로 엔트리 검색 (첫 매칭 반환)
  static SheetAliasEntry? findBySpreadsheetId(String rawIdOrUrl) {
    final id = normalizeSpreadsheetId(rawIdOrUrl);
    if (id.isEmpty) return null;
    for (final e in entriesNotifier.value) {
      if (e.spreadsheetId == id) return e;
    }
    return null;
  }

  /// "추가" semantics: alias가 이미 있으면 예외(또는 무시) 처리
  static Future<void> addEntry({
    required String alias,
    required String spreadsheetId,
    bool setActiveForNotice = false,
    bool setActiveForChat = false,
  }) async {
    await ensureBootstrapped();
    final a = alias.trim();
    if (a.isEmpty) throw ArgumentError('alias is invalid');

    if (entriesNotifier.value.any((e) => e.alias == a)) {
      throw ArgumentError('alias already exists');
    }

    await upsert(
      alias: a,
      rawIdOrUrl: spreadsheetId,
      setActiveForNotice: setActiveForNotice,
      setActiveForChat: setActiveForChat,
    );
  }

  /// "수정" semantics:
  /// - oldAlias -> newAlias로 rename(필요시)
  /// - newSpreadsheetId로 upsert
  static Future<void> updateEntry({
    required String oldAlias,
    required String newAlias,
    required String newSpreadsheetId,
  }) async {
    await ensureBootstrapped();

    final o = oldAlias.trim();
    final n = newAlias.trim();
    if (o.isEmpty || n.isEmpty) throw ArgumentError('alias is invalid');

    final exists = entriesNotifier.value.any((e) => e.alias == o);
    if (!exists) throw ArgumentError('old alias not found');

    // alias 변경
    if (o != n) {
      await renameAlias(oldAlias: o, newAlias: n);
    }

    // id 변경(같아도 upsert는 최신화만 수행)
    await upsert(alias: n, rawIdOrUrl: newSpreadsheetId);
  }

  /// alias 기반 삭제
  static Future<void> removeEntry(String alias) async {
    await removeAlias(alias);
  }
}
