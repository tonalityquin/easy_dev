import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
///
/// 반영 사항:
/// 1) 전송: values.append(원자적 append, 경합/비용 감소)
/// 2) 폴링: 앱 라이프사이클 연동(백그라운드 stop / 포그라운드 resume)
/// 3) 폴링: 백오프 + 저빈도화(채팅 UI 닫힘 상태에서는 느린 주기)
/// 4) 운영개선: ref-count 기반 acquire()/release() → 구독자 0이면 폴링 완전 중단
/// 5) 운영비 개선: 증분 fetch(마지막 seen row부터 읽기) 도입
class SheetChatService with WidgetsBindingObserver {
  SheetChatService._();

  static final SheetChatService instance = SheetChatService._();

  /// UI는 이 상태만 구독하면 됨
  final ValueNotifier<SheetChatState> state =
  ValueNotifier<SheetChatState>(SheetChatState.empty);

  // scopeKey(현재 구역)
  String _scopeKey = '';

  // 현재 spreadsheetId
  String _spreadsheetId = '';

  // fetching guard
  bool _isFetching = false;

  // 간단 직렬화 락(동시 send/clear/fetch 충돌 완화)
  Future<void> _opChain = Future.value();

  /// 한 번에 표시할 최대 메시지 수(뷰 성능)
  static const int maxMessagesInUi = 80;

  // ─────────────────────────────────────────────────────────────
  // ✅ ref-count(구독자 카운트): 구독자 0이면 폴링 완전 중단
  // ─────────────────────────────────────────────────────────────

  int _refCount = 0;

  /// acquire: 이 서비스를 "사용 중"으로 등록 (UI가 실제로 열릴 때 호출)
  Future<void> acquire(String scopeKey, {bool forceFetch = true}) async {
    await _ensureNotificationsInitialized();
    _attachLifecycleObserverIfNeeded();

    final wasZero = _refCount == 0;
    _refCount++;

    if (wasZero) {
      _desiredRunning = true;
    }

    await updateScope(scopeKey, forceFetch: forceFetch || wasZero);

    // 백그라운드면 resume에서 재개
    if (_appInBackground) return;

    // 폴링 스케줄 보장
    _reschedulePolling(reason: wasZero ? 'acquire_first' : 'acquire_more');
  }

  /// release: 이 서비스를 "사용 종료"로 등록 (UI가 닫힐 때 호출)
  void release() {
    if (_refCount <= 0) return;
    _refCount--;

    if (_refCount == 0) {
      _desiredRunning = false;
      _cancelPollingTimer();
      _consecutiveFailures = 0;

      // 테스트/품질을 위해 observer 해제
      _detachLifecycleObserverIfPossible();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 알림 UX 플래그/정책
  // ─────────────────────────────────────────────────────────────

  bool _chatUiVisible = false; // 팝오버가 열려 있는 동안 true(알림 억제 목적)
  bool _suppressWhenChatVisible = true;

  ChatNotifyMode _notifyMode = ChatNotifyMode.summaryOne;

  /// individualUpToN 모드에서 최대 알림 개수
  int _maxIndividualNotifications = 3;

  /// ✅ 알림 초기화를 서비스에서 보장
  bool _notiInitialized = false;

  Future<void> _ensureNotificationsInitialized() async {
    if (_notiInitialized) return;
    _notiInitialized = true;
    try {
      await ChatLocalNotificationService.instance.ensureInitialized();
    } catch (_) {
      // 알림 권한 거부/초기화 실패가 채팅 기능 전체를 망가뜨리지 않도록 무시
    }
  }

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
      _maxIndividualNotifications = maxIndividualNotifications.clamp(1, 20);
    }
  }

  void setChatUiVisible(bool visible) {
    final changed = _chatUiVisible != visible;
    _chatUiVisible = visible;

    // 채팅 UI 열림/닫힘에 따라 폴링 주기 재스케줄
    if (changed) {
      _reschedulePolling(reason: 'chatUiVisibleChanged');
    }
  }

  bool get shouldSuppressNotifications =>
      _suppressWhenChatVisible && _chatUiVisible;

  // ─────────────────────────────────────────────────────────────
  // ✅ lastSeen 델타 판정/저장용 캐시
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

  // signature에서 row 번호 추출: "...|row123"
  int? _extractRowFromSignature(String sig) {
    final m = RegExp(r'\|row(\d+)$').firstMatch(sig.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 폴링: 라이프사이클 연동 + 백오프 + 저빈도화
  // ─────────────────────────────────────────────────────────────

  // 기본 주기: 채팅 UI가 열려 있을 때(고빈도)
  static const Duration _activePollInterval = Duration(seconds: 3);

  // 저빈도: 채팅 UI가 닫혀 있을 때(가능하면 느리게)
  static const Duration _idlePollInterval = Duration(seconds: 12);

  // 최대 백오프 상한
  static const Duration _maxBackoff = Duration(seconds: 60);

  int _consecutiveFailures = 0;
  Timer? _pollTimer;

  bool _desiredRunning = false;
  bool _appInBackground = false;

  bool _observerAttached = false;
  final math.Random _rng = math.Random();

  void _attachLifecycleObserverIfNeeded() {
    if (_observerAttached) return;
    _observerAttached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _detachLifecycleObserverIfPossible() {
    if (!_observerAttached) return;
    if (_refCount == 0) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _appInBackground = true;
      _cancelPollingTimer();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _appInBackground = false;

      if (_refCount > 0 && _desiredRunning) {
        () async {
          await _fetchLatest(force: true);
          _reschedulePolling(reason: 'lifecycleResumed');
        }();
      }
    }
  }

  void _cancelPollingTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Duration _basePollInterval() {
    return _chatUiVisible ? _activePollInterval : _idlePollInterval;
  }

  Duration _computeNextPollDelay() {
    final base = _basePollInterval();

    if (_consecutiveFailures <= 0) return base;

    // 지수 백오프: base * 2^n, 상한 적용
    final cappedN = _consecutiveFailures.clamp(1, 6); // 최대 64배
    final mult = 1 << cappedN;

    final rawMs = base.inMilliseconds * mult;
    final clampedMs = math.min(rawMs, _maxBackoff.inMilliseconds);

    // jitter(0~10%)
    final jitter = (clampedMs * (_rng.nextDouble() * 0.10)).round();
    final withJitter = clampedMs + jitter;

    return Duration(milliseconds: withJitter);
  }

  void _notePollSuccess() {
    if (_consecutiveFailures != 0) _consecutiveFailures = 0;
  }

  void _notePollFailure() {
    _consecutiveFailures = (_consecutiveFailures + 1).clamp(0, 50);
  }

  void _scheduleNextPoll({String? reason}) {
    _cancelPollingTimer();

    if (_refCount <= 0) return;
    if (!_desiredRunning) return;
    if (_appInBackground) return;

    final delay = _computeNextPollDelay();

    _pollTimer = Timer(delay, () {
      _pollTimer = null;
      () async {
        await _fetchLatest();
        _scheduleNextPoll(reason: reason ?? 'tick');
      }();
    });
  }

  void _reschedulePolling({String? reason}) {
    if (_refCount <= 0) return;
    if (!_desiredRunning) return;
    if (_appInBackground) return;
    _scheduleNextPoll(reason: reason ?? 'reschedule');
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Public helpers: scope 변경/강제 새로고침
  // ─────────────────────────────────────────────────────────────

  Future<void> updateScope(String scopeKey, {bool forceFetch = true}) async {
    final key = scopeKey.trim();
    final sameScope = _scopeKey == key;
    if (!sameScope) {
      _scopeKey = key;
      _resetDeltaCachesOnContextChange();
    }

    // running 상태가 아니면 scope만 잡아두고 종료
    if (_refCount <= 0 || !_desiredRunning || _appInBackground) return;

    // scope 변경이나 forceFetch이면 강제 로드
    await _fetchLatest(force: forceFetch || !sameScope || state.value.messages.isEmpty);
    _reschedulePolling(reason: 'updateScope');
  }

  Future<void> refresh({String? scopeKey}) async {
    if (scopeKey != null && scopeKey.trim().isNotEmpty) {
      await updateScope(scopeKey, forceFetch: false);
    }

    if (_refCount <= 0 || !_desiredRunning || _appInBackground) return;

    await _fetchLatest(force: true);
    _reschedulePolling(reason: 'manual_refresh');
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Sheets / locking
  // ─────────────────────────────────────────────────────────────

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
  // ✅ 헤더 감지 / 전송(append) / 삭제
  // ─────────────────────────────────────────────────────────────

  Future<bool> _hasHeaderRow(sheets.SheetsApi api, String sid) async {
    try {
      final headResp =
      await api.spreadsheets.values.get(sid, kChatHeaderProbeRange);
      final headRow = (headResp.values != null && headResp.values!.isNotEmpty)
          ? headResp.values!.first
          : null;

      if (headRow == null || headRow.isEmpty) return false;

      final a = (headRow[0] ?? '').toString().trim();
      final b = (headRow.length > 1 ? (headRow[1] ?? '') : '').toString().trim();
      final c = (headRow.length > 2 ? (headRow[2] ?? '') : '').toString().trim();

      // A1이 ISO datetime이면 헤더가 아닌 것으로 판단
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
        _notePollFailure();
        _reschedulePolling(reason: 'sendMessage_noSpreadsheetId');
        return;
      }

      Future<void> doSendOnce() async {
        final api = await _sheetsApi();
        final nowUtc = DateTime.now().toUtc().toIso8601String();

        final vr = sheets.ValueRange(values: [
          [nowUtc, msg],
        ]);

        await api.spreadsheets.values.append(
          vr,
          spreadsheetId,
          '$kChatSheetName!A:B',
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
        );

        // ✅ 자기 알림 억제(전송 직후 폴링 반영 시)
        ChatLocalNotificationService.instance.markSelfSent(msg);

        await _fetchLatest(force: true);
        _reschedulePolling(reason: 'sendMessage_success');
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
            _notePollFailure();
            _reschedulePolling(reason: 'sendMessage_failed_after_refresh');
            return;
          }
        }

        state.value =
            state.value.copyWith(loading: false, error: '채팅 전송 실패: $e');
        _notePollFailure();
        _reschedulePolling(reason: 'sendMessage_failed');
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
        _notePollFailure();
        _reschedulePolling(reason: 'clear_noSpreadsheetId');
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

        state.value =
        const SheetChatState(loading: false, error: null, messages: []);

        // ✅ clear 시 lastSeen도 초기화(스팸 방지)
        await _saveLastSeen(sid, '');
      }

      try {
        await doClearOnce();
        _reschedulePolling(reason: 'clear_success');
      } catch (e) {
        if (GoogleAuthSession.isInvalidTokenError(e)) {
          try {
            await GoogleAuthSession.instance.refreshIfNeeded();
            await doClearOnce();
            _reschedulePolling(reason: 'clear_success_after_refresh');
            return;
          } catch (e2) {
            final msg2 = GoogleAuthSession.isInvalidTokenError(e2)
                ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
                : '채팅 삭제 실패: $e2';
            state.value = state.value.copyWith(loading: false, error: msg2);
            _notePollFailure();
            _reschedulePolling(reason: 'clear_failed_after_refresh');
            return;
          }
        }

        state.value =
            state.value.copyWith(loading: false, error: '채팅 삭제 실패: $e');
        _notePollFailure();
        _reschedulePolling(reason: 'clear_failed');
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 최신 로드 + 델타 판정 + 알림(정책/억제 반영)
  //   - force=true: full fetch
  //   - force=false: 가능하면 증분 fetch(row 기반)
  // ─────────────────────────────────────────────────────────────

  Future<void> _fetchLatest({bool force = false}) async {
    // release 직후 등 레이스로 호출되는 경우 방어
    if (_refCount <= 0 || !_desiredRunning || _appInBackground) return;

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
        _notePollFailure();
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

      // ✅ 증분 fetch 시도 조건:
      // - force가 아니고
      // - spreadsheet가 바뀌지 않았고
      // - prevSig가 있고
      // - 기존 UI 메시지가 있고
      final prevSig = _lastSeenSig.trim();
      final prevRow = _extractRowFromSignature(prevSig);

      final canIncremental = !force &&
          !spreadsheetChanged &&
          prevSig.isNotEmpty &&
          prevRow != null &&
          prevRow > 0 &&
          state.value.messages.isNotEmpty;

      if (canIncremental) {
        final ok = await _fetchIncremental(
          api: api,
          sid: sid,
          fromRow: prevRow,
          prevSig: prevSig,
        );

        if (ok) {
          _notePollSuccess();
          return;
        }

        // 증분 실패(시트 편집/정렬/clear 등) → full fetch로 복구(스팸 방지 정책 유지)
      }

      await _fetchFull(api: api, sid: sid, force: force || spreadsheetChanged);

      _notePollSuccess();
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
          _notePollFailure();
          return;
        }
      }

      state.value =
          state.value.copyWith(loading: false, error: '채팅 불러오기 실패: $e');
      _notePollFailure();
    } finally {
      _isFetching = false;
    }
  }

  Future<bool> _fetchIncremental({
    required sheets.SheetsApi api,
    required String sid,
    required int fromRow,
    required String prevSig,
  }) async {
    // prev row부터 읽어서 prevSig를 포함한 뒤 newRows만 계산
    final range = '$kChatSheetName!A$fromRow:C';
    final resp = await api.spreadsheets.values.get(sid, range);
    final rows = resp.values ?? const <List<Object?>>[];

    // clear된 경우: 응답이 비면(특히 fromRow가 큰 경우) 메시지/lastSeen 초기화
    if (rows.isEmpty) {
      if (state.value.messages.isNotEmpty) {
        state.value = const SheetChatState(loading: false, error: null, messages: []);
        await _saveLastSeen(sid, '');
      }
      return true;
    }

    final parsed = <_ParsedRow>[];

    for (int j = 0; j < rows.length; j++) {
      final row = rows[j];
      final sheetRowNumber = fromRow + j;

      final tsRaw = row.isNotEmpty ? (row[0] ?? '').toString().trim() : '';

      String msgRaw = '';
      if (row.length >= 3) {
        msgRaw = (row[2] ?? '').toString().trim(); // 구형: C열
      } else if (row.length >= 2) {
        msgRaw = (row[1] ?? '').toString().trim(); // 신형: B열
      }

      if (msgRaw.isEmpty) continue;

      DateTime? t;
      if (tsRaw.isNotEmpty) t = DateTime.tryParse(tsRaw);

      final sig = '${tsRaw}|${msgRaw}|row$sheetRowNumber';

      parsed.add(
        _ParsedRow(
          msg: SheetChatMessage(time: t, text: msgRaw),
          signature: sig,
        ),
      );
    }

    if (parsed.isEmpty) return true;

    // prevSig가 이 증분 chunk 안에 있어야 정상
    final idx = parsed.indexWhere((e) => e.signature == prevSig);
    if (idx < 0) {
      // 증분으로 복구 불가(정렬/삭제/삽입 등) → full fetch로 fallback
      return false;
    }

    final latestSig = parsed.last.signature;

    // new rows
    final newRows = (idx + 1 <= parsed.length - 1) ? parsed.sublist(idx + 1) : <_ParsedRow>[];

    if (latestSig.isNotEmpty && latestSig != prevSig) {
      await _saveLastSeen(sid, latestSig);
    }

    // 알림(억제/다건 정책 반영)
    if (newRows.isNotEmpty && !shouldSuppressNotifications) {
      final nonSelf = <_ParsedRow>[];
      for (final r in newRows) {
        if (!ChatLocalNotificationService.instance.isLikelySelfSent(r.msg.text)) {
          nonSelf.add(r);
        }
      }

      if (nonSelf.isNotEmpty) {
        if (_notifyMode == ChatNotifyMode.summaryOne) {
          final last = nonSelf.last.msg;
          await ChatLocalNotificationService.instance.showChatMessage(
            scopeKey: _scopeKey,
            message: last.text,
            countHint: nonSelf.length,
          );
        } else {
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

    // UI 메시지: 기존 + new만 append 후 trim
    final appended = <SheetChatMessage>[
      ...state.value.messages,
      ...newRows.map((e) => e.msg),
    ];

    final uiMessages = appended.length <= maxMessagesInUi
        ? appended
        : appended.sublist(appended.length - maxMessagesInUi);

    state.value = SheetChatState(
      loading: false,
      error: null,
      messages: uiMessages,
    );

    return true;
  }

  Future<void> _fetchFull({
    required sheets.SheetsApi api,
    required String sid,
    required bool force,
  }) async {
    final resp = await api.spreadsheets.values.get(sid, kChatReadRange);
    final rows = resp.values ?? const <List<Object?>>[];

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

      // signature: timestamp + message + rowIndex(기존 정책 유지)
      final sig = '${tsRaw}|${msgRaw}|row${i + 1}';

      parsed.add(
        _ParsedRow(
          msg: SheetChatMessage(time: t, text: msgRaw),
          signature: sig,
        ),
      );
    }

    final uiMessages = parsed.length <= maxMessagesInUi
        ? parsed.map((e) => e.msg).toList()
        : parsed.sublist(parsed.length - maxMessagesInUi).map((e) => e.msg).toList();

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
        // lastSeenSig를 찾지 못함: clear/정렬/대량편집 가능성
        // 스팸 방지: 알림 없이 lastSeen만 최신으로 리셋
        await _saveLastSeen(sid, latestSig);
      }
    }

    // 알림(억제/다건 정책 반영)
    if (newRows.isNotEmpty && !shouldSuppressNotifications) {
      final nonSelf = <_ParsedRow>[];
      for (final r in newRows) {
        if (!ChatLocalNotificationService.instance.isLikelySelfSent(r.msg.text)) {
          nonSelf.add(r);
        }
      }

      if (nonSelf.isNotEmpty) {
        if (_notifyMode == ChatNotifyMode.summaryOne) {
          final last = nonSelf.last.msg;
          await ChatLocalNotificationService.instance.showChatMessage(
            scopeKey: _scopeKey,
            message: last.text,
            countHint: nonSelf.length,
          );
        } else {
          final n = _maxIndividualNotifications.clamp(1, 20);
          final slice =
          (nonSelf.length <= n) ? nonSelf : nonSelf.sublist(nonSelf.length - n);

          for (final r in slice) {
            await ChatLocalNotificationService.instance.showChatMessage(
              scopeKey: _scopeKey,
              message: r.msg.text,
            );
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
}
