import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/sheet_chat_service.dart';
import '../../noti_package/shared_spreadsheet_registry.dart';
import 'local_chat_service.dart';

/// ✅ 하드코딩된(초기 기본) 스프레드시트 ID (fallback)
const String kHardcodedChatSpreadsheetId =
    '1_vrpbzOCffEXp8HJ4FaHusWkXaTXSNuokX3JaUjrFX4';

/// ✅ Sheets API 사용 여부 저장 키 (기본 OFF)
const String kChatUseSheetsApiKey = 'chat_use_sheets_api_v1';

/// ✅ currentArea가 없어도 열리도록 fallback scopeKey
const String kFallbackScopeKey = 'global';

/// ✅ 채팅 런타임(모드 스위칭 + 상태 브리징)
/// - OFF(기본): LocalChatService 사용
/// - ON: SheetChatService 사용 + (공용 레지스트리에서) 선택된 스프레드시트 ID를 prefs에 자동 주입
class ChatRuntime {
  ChatRuntime._();

  static final ChatRuntime instance = ChatRuntime._();

  final ValueNotifier<bool> useSheetsApi = ValueNotifier<bool>(false);

  /// UI는 이 state만 구독하면 됨 (현재 모드의 state를 브리징)
  final ValueNotifier<SheetChatState> state =
  ValueNotifier<SheetChatState>(SheetChatState.empty);

  String _scopeKey = kFallbackScopeKey;

  Future<void>? _initFuture;

  ValueNotifier<SheetChatState>? _boundSource;
  VoidCallback? _boundListener;

  VoidCallback? _registryListener;

  Future<void> ensureInitialized() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(kChatUseSheetsApiKey) ?? false; // ✅ 기본 OFF
    useSheetsApi.value = v;

    // ✅ 공용 레지스트리 초기화(공지/채팅 동일 키)
    await SharedSpreadsheetRegistry.ensureBootstrapped();

    // ✅ (중요) 채팅 활성 별명 변경을 런타임에 반영
    _registryListener ??= () {
      // 리스너는 sync void이므로 microtask로 분리
      scheduleMicrotask(() async {
        await ensureInitialized();
        if (!useSheetsApi.value) return; // OFF면 선택만 저장(나중에 ON 시 반영)
        await _applyMode(forceRestart: true);
      });
    };
    SharedSpreadsheetRegistry.activeChatAliasNotifier.addListener(_registryListener!);

    // 초기 모드에 맞는 소스 바인딩
    _bindTo(useSheetsApi.value
        ? SheetChatService.instance.state
        : LocalChatService.instance.state);

    state.value = _boundSource?.value ?? SheetChatState.empty;

    // ON이면 초기에도 sheetId 주입
    if (useSheetsApi.value) {
      await _applyMode(forceRestart: true);
    }
  }

  String get scopeKey => _scopeKey;

  Future<void> setScopeKey(String scopeKey) async {
    await ensureInitialized();
    final key = scopeKey.trim().isEmpty ? kFallbackScopeKey : scopeKey.trim();
    _scopeKey = key;
  }

  Future<void> setUseSheetsApi(bool v) async {
    await ensureInitialized();

    if (useSheetsApi.value == v) return;
    useSheetsApi.value = v;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kChatUseSheetsApiKey, v);

    // 모드 변경 즉시 반영
    await _applyMode(forceRestart: true);
  }

  Future<void> start(String scopeKey) async {
    await ensureInitialized();
    final key = scopeKey.trim().isEmpty ? kFallbackScopeKey : scopeKey.trim();

    final sameScope = _scopeKey == key;
    _scopeKey = key;

    await _applyMode(forceRestart: !sameScope);
  }

  Future<void> refresh() async {
    await ensureInitialized();

    if (useSheetsApi.value) {
      await SheetChatService.instance.start(_scopeKey);
    } else {
      await LocalChatService.instance.refresh();
    }
  }

  Future<void> sendMessage(String text) async {
    await ensureInitialized();

    if (useSheetsApi.value) {
      await SheetChatService.instance.sendMessage(text);
    } else {
      await LocalChatService.instance.sendMessage(text);
    }
  }

  /// ✅ (호환 유지) spreadsheetId로 호출해도 동작하도록:
  /// - 공용 레지스트리에서 id에 매칭되는 alias를 찾아 채팅 활성 별명으로 설정
  /// - Sheets ON이면 즉시 재시작
  Future<void> selectSheetAndRestart(String spreadsheetId) async {
    await ensureInitialized();

    final id = spreadsheetId.trim();
    if (id.isEmpty) return;

    await SharedSpreadsheetRegistry.ensureBootstrapped();
    final entry = SharedSpreadsheetRegistry.findBySpreadsheetId(id);
    if (entry == null) return;

    await SharedSpreadsheetRegistry.setActiveAlias(HeadSheetFeature.chat, entry.alias);

    if (!useSheetsApi.value) return;

    // 즉시 재시작
    await _applyMode(forceRestart: true);
  }

  Future<void> _applyMode({required bool forceRestart}) async {
    if (useSheetsApi.value) {
      await SharedSpreadsheetRegistry.ensureBootstrapped();

      final resolved = SharedSpreadsheetRegistry.activeSpreadsheetIdOf(HeadSheetFeature.chat);
      final sheetId = (resolved != null && resolved.trim().isNotEmpty)
          ? resolved.trim()
          : kHardcodedChatSpreadsheetId;

      // ✅ ON: 선택된 스프레드시트 ID를 prefs에 주입 (SheetChatService가 참조)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSharedSpreadsheetIdKey, sheetId);

      if (forceRestart) {
        SheetChatService.instance.stop();
      }

      _bindTo(SheetChatService.instance.state);
      await SheetChatService.instance.start(_scopeKey);
    } else {
      // ✅ OFF(기본): Sheets 폴링 중단 + 로컬 사용
      SheetChatService.instance.stop();

      _bindTo(LocalChatService.instance.state);
      await LocalChatService.instance.start(_scopeKey, force: forceRestart);
    }
  }

  void _bindTo(ValueNotifier<SheetChatState> src) {
    if (_boundSource == src) return;

    if (_boundSource != null && _boundListener != null) {
      _boundSource!.removeListener(_boundListener!);
    }

    _boundSource = src;
    state.value = src.value;

    void listener() {
      state.value = src.value;
    }

    _boundListener = listener;
    src.addListener(listener);
  }
}
