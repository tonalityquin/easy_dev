// lib/services/sheet_chat_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/google_auth_session.dart';
import 'chat_local_notification_service.dart';

/// ✅ Header에서 저장한 "스프레드시트 ID" SharedPreferences 키와 동일해야 함.
const String kSharedSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

/// ✅ (중요) 채팅 시트명 고정: chat
const String kChatSheetName = 'chat';

/// ✅ 채팅 Range: 하위호환(구형 C열까지 포함)을 위해 A:C로 읽음
const String kChatReadRange = '$kChatSheetName!A:C';

/// ✅ 채팅 시트의 헤더 감지용(1행 확인)
const String kChatHeaderProbeRange = '$kChatSheetName!A1:C1';

/// ✅ (추가) "마지막으로 본 메시지" signature 저장 키 prefix
const String kChatLastSeenSigPrefix = 'chat_last_seen_sig_v2';

/// ✅ 새 메시지 알림 모드
enum ChatNotifyMode {
  /// 새 메시지가 여러 개여도 요약 알림 1개(기본)
  summaryOne,

  /// 최대 N개까지 개별 알림
  individualUpToN,
}

/// ✅ 시트 기반 채팅 메시지(익명)
class SheetChatMessage {
  final DateTime? time;
  final String text;

  const SheetChatMessage({
    required this.time,
    required this.text,
  });
}

/// ✅ 전역 상태(버튼/패널 공용)
class SheetChatState {
  final bool loading;
  final String? error;
  final List<SheetChatMessage> messages;

  const SheetChatState({
    required this.loading,
    required this.error,
    required this.messages,
  });

  SheetChatMessage? get latest => messages.isEmpty ? null : messages.last;

  SheetChatState copyWith({
    bool? loading,
    String? error,
    List<SheetChatMessage>? messages,
  }) {
    return SheetChatState(
      loading: loading ?? this.loading,
      error: error,
      messages: messages ?? this.messages,
    );
  }

  static const empty = SheetChatState(loading: false, error: null, messages: []);
}

/// ✅ 내부용: signature 포함(새 메시지 델타 판정용)
class _ParsedRow {
  final SheetChatMessage msg;
  final String signature;

  const _ParsedRow({
    required this.msg,
    required this.signature,
  });
}

/// ✅ Google Sheets 기반 공개(익명) 채팅 서비스
/// - polling으로 주기적 갱신
/// - (핵심) lastSeen signature 기반 델타 판정으로 "새 메시지"만 알림
///
/// ✅ 추가 요구 반영:
/// 1) "채팅 팝오버가 열려 있는 동안에는 알림 억제" 플래그 제공
///    - setChatUiVisible(true/false)
/// 2) 새 메시지 다건 처리:
///    - summaryOne: 요약 1개
///    - individualUpToN: 최대 N개 개별 알림
class SheetChatService {
  SheetChatService._();

  static final SheetChatService instance = SheetChatService._();

  /// UI는 이 상태만 구독하면 됨
  final ValueNotifier<SheetChatState> state =
  ValueNotifier<SheetChatState>(SheetChatState.empty);

  // 화면/영역 전환 시 polling 재시작 용도로만 scopeKey 유지
  String _scopeKey = '';

  // 현재 spreadsheetId
  String _spreadsheetId = '';

  // polling
  Timer? _timer;
  bool _isFetching = false;

  // 간단 직렬화 락(동시 send/clear/fetch 충돌 완화)
  Future<void> _opChain = Future.value();

  // polling 주기(원하면 조정)
  static const Duration pollInterval = Duration(seconds: 3);

  /// 한 번에 표시할 최대 메시지 수(뷰 성능)
  static const int maxMessagesInUi = 80;

  // ─────────────────────────────────────────────────────────────
  // ✅ 알림 UX 플래그/정책
  // ─────────────────────────────────────────────────────────────

  bool _chatUiVisible = false; // 팝오버가 열려 있는 동안 true로 설정(알림 억제 목적)
  bool _suppressWhenChatVisible = true;

  ChatNotifyMode _notifyMode = ChatNotifyMode.summaryOne;

  /// individualUpToN 모드에서 최대 알림 개수
  int _maxIndividualNotifications = 3;

  /// 알림 정책 설정(원하는 곳에서 호출)
  void configureNotifications({
    bool? suppressWhenChatVisible,
    ChatNotifyMode? mode,
    int? maxIndividualNotifications,
  }) {
    if (suppressWhenChatVisible != null) {
      _suppressWhenChatVisible = suppressWhenChatVisible;
    }
    if (mode != null) {
      _notifyMode = mode;
    }
    if (maxIndividualNotifications != null) {
      _maxIndividualNotifications =
          maxIndividualNotifications.clamp(1, 20);
    }
  }

  /// ✅ 팝오버(채팅 UI)가 열려 있는 동안 true로 설정
  /// - true인 동안 알림 억제(기본 on)
  void setChatUiVisible(bool visible) {
    _chatUiVisible = visible;
  }

  bool get isChatUiVisible => _chatUiVisible;

  bool get shouldSuppressNotifications =>
      _suppressWhenChatVisible && _chatUiVisible;

  // ─────────────────────────────────────────────────────────────
  // ✅ 새 메시지 델타 판정/저장용 캐시
  // ─────────────────────────────────────────────────────────────

  bool _lastSeenLoaded = false;
  String _lastSeenSig = '';
  String _lastSeenCacheKey = '';

  bool _headerChecked = false;
  bool _hasHeaderCached = false;

  String _sanitizeKey(String s) {
    final trimmed = s.trim();
    final safe = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    return safe.isEmpty ? 'na' : safe;
  }

  String _makeLastSeenPrefsKey(String sid, String scopeKey) {
    final a = _sanitizeKey(sid);
    final b = _sanitizeKey(scopeKey);
    return '${kChatLastSeenSigPrefix}__${a}__${b}';
  }

  Future<void> _loadLastSeenIfNeeded(String sid) async {
    final key = _makeLastSeenPrefsKey(sid, _scopeKey);
    if (_lastSeenLoaded && _lastSeenCacheKey == key) return;

    _lastSeenCacheKey = key;
    _lastSeenLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    _lastSeenSig = (prefs.getString(key) ?? '').trim();
  }

  Future<void> _saveLastSeen(String sid, String sig) async {
    final key = _makeLastSeenPrefsKey(sid, _scopeKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, sig);

    _lastSeenCacheKey = key;
    _lastSeenSig = sig;
    _lastSeenLoaded = true;
  }

  void _resetDeltaCachesOnContextChange() {
    _lastSeenLoaded = false;
    _lastSeenSig = '';
    _lastSeenCacheKey = '';

    _headerChecked = false;
    _hasHeaderCached = false;
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 시작/정지
  // ─────────────────────────────────────────────────────────────

  Future<void> start(String scopeKey) async {
    final key = scopeKey.trim();

    final sameScope = _scopeKey == key;
    _scopeKey = key;

    if (!sameScope) {
      _resetDeltaCachesOnContextChange();
    }

    if (sameScope && _timer != null) return;

    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _fetchLatest());

    await _fetchLatest(force: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<sheets.SheetsApi> _sheetsApi() async {
    final client = await GoogleAuthSession.instance.safeClient();
    return sheets.SheetsApi(client);
  }

  Future<String> _loadSpreadsheetIdFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(kSharedSpreadsheetIdKey) ?? '').trim();
  }

  Future<T> _runLocked<T>(Future<T> Function() action) async {
    final prev = _opChain;
    final completer = Completer<void>();
    _opChain = completer.future;

    await prev;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 헤더 감지 / 빈 행 찾기 / 전송 / 삭제
  // ─────────────────────────────────────────────────────────────

  Future<bool> _hasHeaderRow(sheets.SheetsApi api, String sid) async {
    try {
      final headResp =
      await api.spreadsheets.values.get(sid, kChatHeaderProbeRange);
      final headRow =
      (headResp.values != null && headResp.values!.isNotEmpty)
          ? headResp.values!.first
          : null;

      if (headRow == null || headRow.isEmpty) return false;

      final a = (headRow[0] ?? '').toString().trim();
      final b = (headRow.length > 1 ? (headRow[1] ?? '') : '').toString().trim();
      final c = (headRow.length > 2 ? (headRow[2] ?? '') : '').toString().trim();

      final dt = DateTime.tryParse(a);
      if (dt != null) return false;

      final aL = a.toLowerCase();
      final bL = b.toLowerCase();
      final cL = c.toLowerCase();

      if (aL.contains('time') ||
          aL.contains('date') ||
          aL.contains('timestamp') ||
          bL.contains('message') ||
          cL.contains('message')) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureHeaderCached(sheets.SheetsApi api, String sid) async {
    if (_headerChecked) return;
    _hasHeaderCached = await _hasHeaderRow(api, sid);
    _headerChecked = true;
  }

  Future<int> _findFirstEmptyRowIndex(sheets.SheetsApi api, String sid) async {
    final hasHeader = await _hasHeaderRow(api, sid);
    final startRow = hasHeader ? 2 : 1;

    final colResp =
    await api.spreadsheets.values.get(sid, '$kChatSheetName!A:A');
    final rows = colResp.values ?? const <List<Object?>>[];

    for (int i = startRow - 1; i < rows.length; i++) {
      final row = rows[i];
      final a = row.isNotEmpty ? (row[0] ?? '').toString().trim() : '';
      if (a.isEmpty) {
        return i + 1;
      }
    }

    final next = rows.length + 1;
    return next < startRow ? startRow : next;
  }

  Future<bool> _isRowEmptyAB(
      sheets.SheetsApi api, String sid, int rowIndex) async {
    final range = '$kChatSheetName!A$rowIndex:B$rowIndex';
    final resp = await api.spreadsheets.values.get(sid, range);
    final values = resp.values;

    if (values == null || values.isEmpty) return true;
    final row = values.first;
    if (row.isEmpty) return true;

    for (final v in row) {
      if ((v ?? '').toString().trim().isNotEmpty) return false;
    }
    return true;
  }

  Future<void> sendMessage(String message) async {
    final msg = message.trim();
    if (msg.isEmpty) return;

    await _runLocked(() async {
      final spreadsheetId = await _loadSpreadsheetIdFromPrefs();
      if (spreadsheetId.isEmpty) {
        state.value = state.value.copyWith(
          loading: false,
          error: '스프레드시트 ID가 설정되어 있지 않습니다. (Header > 앱 설정에서 설정)',
        );
        return;
      }

      Future<void> doSendOnce() async {
        final api = await _sheetsApi();
        final nowUtc = DateTime.now().toUtc().toIso8601String();

        final vr = sheets.ValueRange(values: [
          [nowUtc, msg],
        ]);

        const int maxRetry = 6;
        bool wrote = false;

        for (int attempt = 0; attempt < maxRetry; attempt++) {
          final rowIndex = await _findFirstEmptyRowIndex(api, spreadsheetId);
          final empty = await _isRowEmptyAB(api, spreadsheetId, rowIndex);
          if (!empty) continue;

          final writeRange = '$kChatSheetName!A$rowIndex:B$rowIndex';

          await api.spreadsheets.values.update(
            vr,
            spreadsheetId,
            writeRange,
            valueInputOption: 'RAW',
          );

          wrote = true;
          break;
        }

        if (!wrote) {
          state.value = state.value.copyWith(
            loading: false,
            error: '채팅 전송 실패: 저장 위치(빈 행) 확보에 실패했습니다. 잠시 후 다시 시도하세요.',
          );
          return;
        }

        // ✅ 자기 알림 억제(전송 직후 폴링 반영 시)
        ChatLocalNotificationService.instance.markSelfSent(msg);

        await _fetchLatest(force: true);
      }

      try {
        await doSendOnce();
      } catch (e) {
        if (GoogleAuthSession.isInvalidTokenError(e)) {
          try {
            await GoogleAuthSession.instance.refreshIfNeeded();
            await doSendOnce();
            return;
          } catch (e2) {
            final msg2 = GoogleAuthSession.isInvalidTokenError(e2)
                ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
                : '채팅 전송 실패: $e2';
            state.value = state.value.copyWith(loading: false, error: msg2);
            return;
          }
        }

        state.value = state.value.copyWith(loading: false, error: '채팅 전송 실패: $e');
      }
    });
  }

  Future<void> clearAllMessages({String? spreadsheetIdOverride}) async {
    await _runLocked(() async {
      final sid = (spreadsheetIdOverride?.trim().isNotEmpty == true)
          ? spreadsheetIdOverride!.trim()
          : await _loadSpreadsheetIdFromPrefs();

      if (sid.isEmpty) {
        state.value = state.value.copyWith(
          loading: false,
          error: '스프레드시트 ID가 설정되어 있지 않습니다. (삭제 실패)',
        );
        return;
      }

      Future<void> doClearOnce() async {
        state.value = state.value.copyWith(loading: true, error: null);

        final api = await _sheetsApi();
        final hasHeader = await _hasHeaderRow(api, sid);

        final rangeToClear = hasHeader ? '$kChatSheetName!A2:C' : kChatReadRange;

        await api.spreadsheets.values.clear(
          sheets.ClearValuesRequest(),
          sid,
          rangeToClear,
        );

        state.value = const SheetChatState(loading: false, error: null, messages: []);

        // ✅ clear 시 lastSeen도 초기화(스팸 방지)
        await _saveLastSeen(sid, '');
      }

      try {
        await doClearOnce();
      } catch (e) {
        if (GoogleAuthSession.isInvalidTokenError(e)) {
          try {
            await GoogleAuthSession.instance.refreshIfNeeded();
            await doClearOnce();
            return;
          } catch (e2) {
            final msg2 = GoogleAuthSession.isInvalidTokenError(e2)
                ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
                : '채팅 삭제 실패: $e2';
            state.value = state.value.copyWith(loading: false, error: msg2);
            return;
          }
        }

        state.value = state.value.copyWith(loading: false, error: '채팅 삭제 실패: $e');
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 최신 로드 + "새 메시지" 델타 판정 + 알림(정책/억제 반영)
  // ─────────────────────────────────────────────────────────────

  Future<void> _fetchLatest({bool force = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    Future<void> doFetchOnce() async {
      final sid = await _loadSpreadsheetIdFromPrefs();
      if (sid.isEmpty) {
        state.value = const SheetChatState(
          loading: false,
          error: '스프레드시트 ID가 설정되어 있지 않습니다. (Header > 앱 설정에서 설정)',
          messages: [],
        );
        _spreadsheetId = '';
        return;
      }

      final spreadsheetChanged = _spreadsheetId != sid;
      _spreadsheetId = sid;

      if (spreadsheetChanged) {
        _resetDeltaCachesOnContextChange();
      }

      await _loadLastSeenIfNeeded(sid);

      if (force || spreadsheetChanged || state.value.messages.isEmpty) {
        state.value = state.value.copyWith(loading: true, error: null);
      }

      final api = await _sheetsApi();

      await _ensureHeaderCached(api, sid);

      final resp = await api.spreadsheets.values.get(sid, kChatReadRange);
      final rows = resp.values ?? const <List<Object?>>[];

      // ✅ 헤더가 있으면 1행 스킵
      final startIndex = _hasHeaderCached ? 1 : 0;

      final parsed = <_ParsedRow>[];

      for (int i = startIndex; i < rows.length; i++) {
        final row = rows[i];

        final tsRaw = row.isNotEmpty ? (row[0] ?? '').toString().trim() : '';

        String msgRaw = '';
        if (row.length >= 3) {
          msgRaw = (row[2] ?? '').toString().trim(); // 구형: C열
        } else if (row.length >= 2) {
          msgRaw = (row[1] ?? '').toString().trim(); // 신형: B열
        }

        if (msgRaw.isEmpty) continue;

        DateTime? t;
        if (tsRaw.isNotEmpty) {
          t = DateTime.tryParse(tsRaw);
        }

        // ✅ signature: timestamp + message + rowIndex(변동성/충돌 최소화)
        final sig = '${tsRaw}|${msgRaw}|row${i + 1}';

        parsed.add(
          _ParsedRow(
            msg: SheetChatMessage(time: t, text: msgRaw),
            signature: sig,
          ),
        );
      }

      // UI 메시지(trim)
      final uiMessages = parsed.length <= maxMessagesInUi
          ? parsed.map((e) => e.msg).toList()
          : parsed
          .sublist(parsed.length - maxMessagesInUi)
          .map((e) => e.msg)
          .toList();

      // ─────────────────────────────────────────
      // ✅ 새 메시지 델타 판정
      // ─────────────────────────────────────────

      final latestSig = parsed.isEmpty ? '' : parsed.last.signature;
      final prevSig = _lastSeenSig.trim();

      List<_ParsedRow> newRows = const [];

      if (prevSig.isEmpty) {
        // 첫 동기화: 알림 없이 lastSeen만 갱신
        if (latestSig.isNotEmpty) {
          await _saveLastSeen(sid, latestSig);
        }
      } else {
        final idx = parsed.indexWhere((e) => e.signature == prevSig);
        if (idx >= 0) {
          if (idx + 1 <= parsed.length - 1) {
            newRows = parsed.sublist(idx + 1);
          }
          if (latestSig.isNotEmpty && latestSig != prevSig) {
            await _saveLastSeen(sid, latestSig);
          }
        } else {
          // lastSeenSig를 찾지 못함: 시트 clear/정렬/대량편집 가능성
          // 스팸 방지: 알림 없이 lastSeen만 최신으로 리셋
          await _saveLastSeen(sid, latestSig);
        }
      }

      // ─────────────────────────────────────────
      // ✅ 알림 발송(억제/다건 정책 반영)
      // ─────────────────────────────────────────
      if (newRows.isNotEmpty) {
        final suppressed = shouldSuppressNotifications;

        if (!suppressed) {
          // 자기 메시지(전송 직후 폴링으로 재유입) 제거
          final nonSelf = <_ParsedRow>[];
          for (final r in newRows) {
            if (!ChatLocalNotificationService.instance.isLikelySelfSent(r.msg.text)) {
              nonSelf.add(r);
            }
          }

          if (nonSelf.isNotEmpty) {
            if (_notifyMode == ChatNotifyMode.summaryOne) {
              // 요약 1개: 마지막 메시지 내용을 body로, countHint로 다건 표시
              final last = nonSelf.last.msg;
              await ChatLocalNotificationService.instance.showChatMessage(
                scopeKey: _scopeKey,
                message: last.text,
                countHint: nonSelf.length,
              );
            } else {
              // 개별 알림: 최신부터 최대 N개
              final n = _maxIndividualNotifications.clamp(1, 20);
              final slice = (nonSelf.length <= n)
                  ? nonSelf
                  : nonSelf.sublist(nonSelf.length - n);

              for (final r in slice) {
                await ChatLocalNotificationService.instance.showChatMessage(
                  scopeKey: _scopeKey,
                  message: r.msg.text,
                );
              }
            }
          }
        }
      }

      state.value = SheetChatState(
        loading: false,
        error: null,
        messages: uiMessages,
      );
    }

    try {
      await doFetchOnce();
    } catch (e) {
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
          await doFetchOnce();
          return;
        } catch (e2) {
          final msg2 = GoogleAuthSession.isInvalidTokenError(e2)
              ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
              : '채팅 불러오기 실패: $e2';
          state.value = state.value.copyWith(loading: false, error: msg2);
          return;
        }
      }

      state.value = state.value.copyWith(loading: false, error: '채팅 불러오기 실패: $e');
    } finally {
      _isFetching = false;
    }
  }
}
