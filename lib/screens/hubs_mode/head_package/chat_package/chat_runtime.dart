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
///
/// ✅ SheetChatService가 ref-count(acquire/release) 기반:
/// - start(): UI가 "표시"될 때 호출(=sheets면 acquire, local이면 start)
/// - stop(): UI가 "사라질 때" 호출(=sheets면 release)
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

  /// ✅ 현재 UI가 채팅 기능을 "사용 중(표시 중)"인지
  bool _active = false;

  /// ✅ sheets 모드에서 acquire 해둔 lease 보유 여부
  bool _sheetsLeaseHeld = false;

  /// 모드 적용 동시성 방지(리스너/토글/스타트가 겹칠 수 있음)
  Future<void> _modeChain = Future.value();

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
    SharedSpreadsheetRegistry.activeChatAliasNotifier
        .addListener(_registryListener!);

    // 초기 모드에 맞는 소스 바인딩(단, 여기서는 "실행"은 하지 않음)
    _bindTo(useSheetsApi.value
        ? SheetChatService.instance.state
        : LocalChatService.instance.state);

    state.value = _boundSource?.value ?? SheetChatState.empty;

    // ON이면 sheetId 주입은 해두되, 실제 acquire는 start()에서만
    if (useSheetsApi.value) {
      await _applyMode(forceRestart: false);
    }
  }

  String get scopeKey => _scopeKey;

  Future<void> setScopeKey(String scopeKey) async {
    await ensureInitialized();
    final key = scopeKey.trim().isEmpty ? kFallbackScopeKey : scopeKey.trim();
    _scopeKey = key;

    // active 상태면 즉시 반영(모드에 따라)
    if (_active) {
      await _applyMode(forceRestart: true);
    }
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

  /// ✅ UI가 채팅 기능을 "표시"할 때 호출(버튼/패널 mount 시)
  /// - sheets면 acquire
  /// - local이면 start
  Future<void> start(String scopeKey) async {
    await ensureInitialized();
    final key = scopeKey.trim().isEmpty ? kFallbackScopeKey : scopeKey.trim();

    final sameScope = _scopeKey == key;
    _scopeKey = key;

    _active = true;
    await _applyMode(forceRestart: !sameScope);
  }

  /// ✅ UI가 채팅 기능을 더 이상 "표시"하지 않을 때 호출(dispose 등)
  /// - sheets면 release(폴링 완전 중단)
  Future<void> stop() async {
    await ensureInitialized();
    _active = false;

    // sheets lease 반납
    if (_sheetsLeaseHeld) {
      SheetChatService.instance.release();
      _sheetsLeaseHeld = false;
    }

    // local은 기존 코드가 stop 개념이 없었으므로 여기서 별도 처리 없음
  }

  Future<void> refresh() async {
    await ensureInitialized();

    // refresh는 보통 UI가 떠 있는 동안 호출된다고 가정
    if (!_active) return;

    if (useSheetsApi.value) {
      // lease 없으면 확보 후 refresh
      if (!_sheetsLeaseHeld) {
        await SheetChatService.instance.acquire(_scopeKey, forceFetch: true);
        _sheetsLeaseHeld = true;
      }
      await SheetChatService.instance.refresh(scopeKey: _scopeKey);
    } else {
      await LocalChatService.instance.refresh();
    }
  }

  Future<void> sendMessage(String text) async {
    await ensureInitialized();

    if (useSheetsApi.value) {
      // sendMessage 자체는 lease 없이도 동작 가능하지만,
      // UI 활성 중이면 lease를 확보해 폴링/갱신이 정상 동작하도록 보장
      if (_active && !_sheetsLeaseHeld) {
        await SheetChatService.instance.acquire(_scopeKey, forceFetch: true);
        _sheetsLeaseHeld = true;
      }
      await SheetChatService.instance.sendMessage(text);
    } else {
      await LocalChatService.instance.sendMessage(text);
    }
  }

  /// ✅ (호환 유지) spreadsheetId로 호출해도 동작하도록:
  /// - 공용 레지스트리에서 id에 매칭되는 alias를 찾아 채팅 활성 별명으로 설정
  /// - Sheets ON이면(그리고 active면) 즉시 반영
  Future<void> selectSheetAndRestart(String spreadsheetId) async {
    await ensureInitialized();

    final id = spreadsheetId.trim();
    if (id.isEmpty) return;

    await SharedSpreadsheetRegistry.ensureBootstrapped();
    final entry = SharedSpreadsheetRegistry.findBySpreadsheetId(id);
    if (entry == null) return;

    await SharedSpreadsheetRegistry.setActiveAlias(
        HeadSheetFeature.chat, entry.alias);

    if (!useSheetsApi.value) return;

    await _applyMode(forceRestart: true);
  }

  Future<void> _applyMode({required bool forceRestart}) async {
    // 동시 호출 직렬화
    _modeChain = _modeChain.then((_) async {
      if (useSheetsApi.value) {
        await SharedSpreadsheetRegistry.ensureBootstrapped();

        final resolved = SharedSpreadsheetRegistry.activeSpreadsheetIdOf(
          HeadSheetFeature.chat,
        );
        final sheetId = (resolved != null && resolved.trim().isNotEmpty)
            ? resolved.trim()
            : kHardcodedChatSpreadsheetId;

        // ✅ ON: 선택된 스프레드시트 ID를 prefs에 주입 (SheetChatService가 참조)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kSharedSpreadsheetIdKey, sheetId);

        // 상태 소스 바인딩
        _bindTo(SheetChatService.instance.state);

        if (_active) {
          // ✅ active일 때만 acquire/refresh
          if (!_sheetsLeaseHeld) {
            await SheetChatService.instance.acquire(_scopeKey, forceFetch: true);
            _sheetsLeaseHeld = true;
          } else {
            // scope/alias 변경 등 반영
            if (forceRestart) {
              await SheetChatService.instance.refresh(scopeKey: _scopeKey);
            } else {
              await SheetChatService.instance.updateScope(
                _scopeKey,
                forceFetch: false,
              );
            }
          }
        } else {
          // ✅ active가 아니면 lease를 잡고 있지 않도록 보장(운영 비용 방지)
          if (_sheetsLeaseHeld) {
            SheetChatService.instance.release();
            _sheetsLeaseHeld = false;
          }
        }
      } else {
        // ✅ OFF(기본): Sheets lease 반납 + 로컬 사용
        if (_sheetsLeaseHeld) {
          SheetChatService.instance.release();
          _sheetsLeaseHeld = false;
        }

        _bindTo(LocalChatService.instance.state);

        if (_active) {
          await LocalChatService.instance.start(_scopeKey,
              force: forceRestart);
        }
      }
    });

    return _modeChain;
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
