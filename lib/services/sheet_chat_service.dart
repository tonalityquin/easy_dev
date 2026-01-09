import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';
import '../utils/google_auth_session.dart';
import '../utils/debug_tags.dart';
import 'chat_local_notification_service.dart';

/// ✅ Header에서 저장한 "스프레드시트 ID" SharedPreferences 키와 동일해야 함.
const String kSharedSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

/// ✅ (중요) 채팅 시트명 고정: chat
const String kChatSheetName = 'chat';

/// ✅ 표준 스키마(v2):
/// A = timestamp(UTC ISO8601)
/// B = message(text)
/// C = messageId(안정적인 델타/중복/정렬 대응용)
///
/// 읽기는 하위호환 위해 A:C 유지
const String kChatReadRange = '$kChatSheetName!A:C';

/// 전송/append는 표준 스키마대로 A:C
const String kChatAppendRange = '$kChatSheetName!A:C';

/// ✅ 채팅 시트의 헤더 감지용(1행 확인)
const String kChatHeaderProbeRange = '$kChatSheetName!A1:C1';

/// ✅ (추가) "마지막으로 본 메시지" 저장 키 prefix
const String kChatLastSeenSigPrefix = 'chat_last_seen_sig_v3';

/// ✅ 새 메시지 알림 모드
enum ChatNotifyMode {
  summaryOne,
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
  final String signature; // v2: id:<messageId>  / legacy: ts|msg|rowN
  final int rowNumber; // sheet row number (1-based)
  final String? messageId;

  const _ParsedRow({
    required this.msg,
    required this.signature,
    required this.rowNumber,
    required this.messageId,
  });
}

/// ✅ lastSeen 구조(v3 저장)
class _LastSeen {
  final String signature;
  final int rowNumber;

  const _LastSeen({required this.signature, required this.rowNumber});
}

/// ✅ header 기반 컬럼 매핑
class _ChatColumnMapping {
  final int timeIdx;
  final int messageIdx;
  final int idIdx;

  const _ChatColumnMapping({
    required this.timeIdx,
    required this.messageIdx,
    required this.idIdx,
  });

  static const defaultV2 = _ChatColumnMapping(timeIdx: 0, messageIdx: 1, idIdx: 2);
}

/// ✅ Google Sheets 기반 공개(익명) 채팅 서비스
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
  // ✅ ref-count: 구독자 0이면 폴링 완전 중단
  // ─────────────────────────────────────────────────────────────

  int _refCount = 0;

  Future<void> acquire(String scopeKey, {bool forceFetch = true}) async {
    await _ensureNotificationsInitialized();
    _attachLifecycleObserverIfNeeded();

    final wasZero = _refCount == 0;
    _refCount++;

    if (wasZero) {
      _desiredRunning = true;
    }

    await updateScope(scopeKey, forceFetch: forceFetch || wasZero);

    if (_appInBackground) return;
    _reschedulePolling(reason: wasZero ? 'acquire_first' : 'acquire_more');
  }

  void release() {
    if (_refCount <= 0) return;
    _refCount--;

    if (_refCount == 0) {
      _desiredRunning = false;
      _cancelPollingTimer();
      _consecutiveFailures = 0;
      _detachLifecycleObserverIfPossible();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 알림 UX 플래그/정책
  // ─────────────────────────────────────────────────────────────

  bool _chatUiVisible = false;
  bool _suppressWhenChatVisible = true;

  ChatNotifyMode _notifyMode = ChatNotifyMode.summaryOne;
  int _maxIndividualNotifications = 3;

  bool _notiInitialized = false;

  Future<void> _ensureNotificationsInitialized() async {
    if (_notiInitialized) return;
    _notiInitialized = true;
    try {
      await ChatLocalNotificationService.instance.ensureInitialized();
    } catch (_) {}
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

    if (changed) {
      _reschedulePolling(reason: 'chatUiVisibleChanged');
    }
  }

  bool get shouldSuppressNotifications => _suppressWhenChatVisible && _chatUiVisible;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직 (DebugApiLogger)
  //   - 폴링 로그 폭주 방지: throttle
  // ─────────────────────────────────────────────────────────────

  static const Duration _logThrottleInterval = Duration(seconds: 30);
  final Map<String, int> _lastLoggedAtMsByKey = <String, int>{};

  bool _shouldLogNow(String key, {Duration interval = _logThrottleInterval}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastLoggedAtMsByKey[key];
    if (last == null || now - last >= interval.inMilliseconds) {
      _lastLoggedAtMsByKey[key] = now;
      return true;
    }
    return false;
  }

  Map<String, dynamic> _debugContext({Map<String, dynamic>? extra}) {
    return <String, dynamic>{
      'scopeKey': _scopeKey,
      'spreadsheetId': _spreadsheetId,
      'refCount': _refCount,
      'desiredRunning': _desiredRunning,
      'appInBackground': _appInBackground,
      'chatUiVisible': _chatUiVisible,
      'consecutiveFailures': _consecutiveFailures,
      if (extra != null) 'extra': extra,
    };
  }

  Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
    bool throttled = true,
  }) async {
    final key = '$tag|${tags?.join(",") ?? ""}';
    if (throttled && !_shouldLogNow(key)) return;

    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          'ctx': _debugContext(extra: extra),
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {}
  }

  void _setError(String msg) {
    state.value = state.value.copyWith(loading: false, error: msg);
  }

  Future<T> _withAuthRetry<T>({
    required String tag,
    required Future<T> Function() action,
    required String userErrorWhenInvalidToken,
    required String userErrorWhenFailed,
    Map<String, dynamic>? extra,
    List<String>? logTags,
  }) async {
    try {
      return await action();
    } catch (e) {
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
          return await action();
        } catch (e2) {
          final msg2 = GoogleAuthSession.isInvalidTokenError(e2)
              ? userErrorWhenInvalidToken
              : '$userErrorWhenFailed: $e2';
          _setError(msg2);
          _notePollFailure();

          await _logApiError(
            tag: '$tag.authRetryFailed',
            message: userErrorWhenFailed,
            error: e2,
            extra: <String, dynamic>{
              'originalError': e.toString(),
              if (extra != null) ...extra,
            },
            tags: logTags,
          );
          rethrow;
        }
      }

      _setError('$userErrorWhenFailed: $e');
      _notePollFailure();

      await _logApiError(
        tag: '$tag.failed',
        message: userErrorWhenFailed,
        error: e,
        extra: extra,
        tags: logTags,
      );
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ lastSeen(v3) 저장/로드
  //   - v3 포맷: "v3|sig=<base64url>|row=<n>"
  //   - legacy 포맷: "<ts>|<msg>|row<n>" (기존 호환)
  // ─────────────────────────────────────────────────────────────

  bool _lastSeenLoaded = false;
  _LastSeen? _lastSeen;
  String _lastSeenCacheKey = '';

  bool _headerChecked = false;
  bool _hasHeaderCached = false;
  _ChatColumnMapping _colMap = _ChatColumnMapping.defaultV2;

  final math.Random _rng = math.Random();

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

  String _encodeLastSeenV3(_LastSeen seen) {
    final sigB64 = base64Url.encode(utf8.encode(seen.signature)).replaceAll('=', '');
    return 'v3|sig=$sigB64|row=${seen.rowNumber}';
  }

  _LastSeen? _decodeLastSeen(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    if (t.startsWith('v3|')) {
      final parts = t.split('|');
      String? sigB64;
      int? row;
      for (final p in parts) {
        if (p.startsWith('sig=')) sigB64 = p.substring('sig='.length);
        if (p.startsWith('row=')) row = int.tryParse(p.substring('row='.length));
      }
      if (sigB64 == null || row == null || row <= 0) return null;

      try {
        final padded = _padBase64(sigB64);
        // ✅ FIX: base64UrlDecode()는 없음 → base64Url.decode()
        final sigBytes = base64Url.decode(padded);
        final sig = utf8.decode(sigBytes);
        return _LastSeen(signature: sig, rowNumber: row);
      } catch (_) {
        return null;
      }
    }

    // legacy: "...|row123"
    final m = RegExp(r'\|row(\d+)$').firstMatch(t);
    final row = (m != null) ? int.tryParse(m.group(1) ?? '') : null;
    if (row != null && row > 0) {
      return _LastSeen(signature: t, rowNumber: row);
    }

    return null;
  }

  String _padBase64(String b64) {
    final mod = b64.length % 4;
    if (mod == 0) return b64;
    return b64 + ('=' * (4 - mod));
  }

  Future<void> _loadLastSeenIfNeeded(String sid) async {
    final key = _makeLastSeenPrefsKey(sid, _scopeKey);
    if (_lastSeenLoaded && _lastSeenCacheKey == key) return;

    _lastSeenCacheKey = key;
    _lastSeenLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(key) ?? '').trim();
    _lastSeen = _decodeLastSeen(raw);
  }

  Future<void> _saveLastSeen(String sid, _LastSeen seen) async {
    final key = _makeLastSeenPrefsKey(sid, _scopeKey);
    final prefs = await SharedPreferences.getInstance();

    // ✅ row=0/empty signature는 “클리어”로 저장(빈 문자열)
    if (seen.signature.trim().isEmpty || seen.rowNumber <= 0) {
      await prefs.setString(key, '');
      _lastSeenCacheKey = key;
      _lastSeen = null;
      _lastSeenLoaded = true;
      return;
    }

    await prefs.setString(key, _encodeLastSeenV3(seen));
    _lastSeenCacheKey = key;
    _lastSeen = seen;
    _lastSeenLoaded = true;
  }

  void _resetDeltaCachesOnContextChange() {
    _lastSeenLoaded = false;
    _lastSeen = null;
    _lastSeenCacheKey = '';

    _headerChecked = false;
    _hasHeaderCached = false;
    _colMap = _ChatColumnMapping.defaultV2;
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 폴링: 라이프사이클 연동 + 백오프 + 저빈도화
  // ─────────────────────────────────────────────────────────────

  static const Duration _activePollInterval = Duration(seconds: 3);
  static const Duration _idlePollInterval = Duration(seconds: 12);
  static const Duration _maxBackoff = Duration(seconds: 60);

  int _consecutiveFailures = 0;
  Timer? _pollTimer;

  bool _desiredRunning = false;
  bool _appInBackground = false;

  bool _observerAttached = false;

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

    final cappedN = _consecutiveFailures.clamp(1, 6);
    final mult = 1 << cappedN;

    final rawMs = base.inMilliseconds * mult;
    final clampedMs = math.min(rawMs, _maxBackoff.inMilliseconds);

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

    if (_refCount <= 0 || !_desiredRunning || _appInBackground) return;

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
  // ✅ 헤더 감지 + 컬럼 매핑
  // ─────────────────────────────────────────────────────────────

  Future<bool> _hasHeaderRow(sheets.SheetsApi api, String sid) async {
    try {
      final headResp = await api.spreadsheets.values.get(sid, kChatHeaderProbeRange);
      final headRow = (headResp.values != null && headResp.values!.isNotEmpty)
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
          bL.contains('text') ||
          cL.contains('message') ||
          cL.contains('id')) {
        return true;
      }
      return false;
    } catch (e) {
      await _logApiError(
        tag: 'SheetChatService._hasHeaderRow',
        message: '헤더 감지 실패',
        error: e,
        extra: <String, dynamic>{
          'sid': sid,
          'range': kChatHeaderProbeRange,
        },
        tags: DebugTags.setForSheetsChat(DebugTags.sheetsChatHeader),
      );
      return false;
    }
  }

  _ChatColumnMapping _inferMappingFromHeaderRow(List<Object?> headRow) {
    int findIndex(List<String> keys) {
      for (int i = 0; i < headRow.length; i++) {
        final s = (headRow[i] ?? '').toString().trim().toLowerCase();
        for (final k in keys) {
          if (s == k || s.contains(k)) return i;
        }
      }
      return -1;
    }

    final timeIdx = findIndex(const ['time', 'timestamp', 'date']);
    final msgIdx = findIndex(const ['message', 'text', 'msg']);
    final idIdx = findIndex(const ['id', 'messageid', 'message_id', 'mid']);

    return _ChatColumnMapping(
      timeIdx: timeIdx >= 0 ? timeIdx : 0,
      messageIdx: msgIdx >= 0 ? msgIdx : 1,
      idIdx: idIdx >= 0 ? idIdx : 2,
    );
  }

  Future<void> _ensureHeaderAndMappingCached(sheets.SheetsApi api, String sid) async {
    if (_headerChecked) return;

    _hasHeaderCached = await _hasHeaderRow(api, sid);
    _headerChecked = true;

    if (_hasHeaderCached) {
      try {
        final headResp = await api.spreadsheets.values.get(sid, kChatHeaderProbeRange);
        final headRow = (headResp.values != null && headResp.values!.isNotEmpty)
            ? headResp.values!.first
            : null;
        if (headRow != null && headRow.isNotEmpty) {
          _colMap = _inferMappingFromHeaderRow(headRow);
        } else {
          _colMap = _ChatColumnMapping.defaultV2;
        }
      } catch (_) {
        _colMap = _ChatColumnMapping.defaultV2;
      }
    } else {
      _colMap = _ChatColumnMapping.defaultV2;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 전송(append): 표준 스키마 A/B/C
  // ─────────────────────────────────────────────────────────────

  String _makeMessageId() {
    final ms = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = _rng.nextInt(1 << 24).toRadixString(36).padLeft(5, '0');
    return '$ms-$r';
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

        await _logApiError(
          tag: 'SheetChatService.sendMessage',
          message: '스프레드시트 ID 미설정으로 전송 불가',
          error: Exception('spreadsheetId is empty'),
          extra: <String, dynamic>{'messageLength': msg.length},
          tags: DebugTags.setForSheetsChat(DebugTags.sheetsChatSend),
        );
        return;
      }

      Future<void> doSendOnce() async {
        final api = await _sheetsApi();
        final nowUtc = DateTime.now().toUtc().toIso8601String();
        final messageId = _makeMessageId();

        final vr = sheets.ValueRange(values: [
          [nowUtc, msg, messageId],
        ]);

        await api.spreadsheets.values.append(
          vr,
          spreadsheetId,
          kChatAppendRange,
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
        );

        ChatLocalNotificationService.instance.markSelfSent(msg);

        await _fetchLatest(force: true);
        _reschedulePolling(reason: 'sendMessage_success');
      }

      try {
        await _withAuthRetry<void>(
          tag: 'SheetChatService.sendMessage',
          action: doSendOnce,
          userErrorWhenInvalidToken: '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.',
          userErrorWhenFailed: '채팅 전송 실패',
          extra: <String, dynamic>{
            'sid': spreadsheetId,
            'appendRange': kChatAppendRange,
            'messageLength': msg.length,
          },
          logTags: DebugTags.setForSheetsChat(DebugTags.sheetsChatSend),
        );

        _notePollSuccess();
      } catch (_) {
        _reschedulePolling(reason: 'sendMessage_failed');
      }
    });
  }

  Future<void> clearAllMessages({String? spreadsheetIdOverride}) async {
    await _runLocked(() async {
      // ✅ FIX: 불필요한 ! 제거 (promotion-friendly)
      final override = spreadsheetIdOverride?.trim();
      final sid = (override != null && override.isNotEmpty)
          ? override
          : await _loadSpreadsheetIdFromPrefs();

      if (sid.isEmpty) {
        state.value = state.value.copyWith(
          loading: false,
          error: '스프레드시트 ID가 설정되어 있지 않습니다. (삭제 실패)',
        );
        _notePollFailure();
        _reschedulePolling(reason: 'clear_noSpreadsheetId');

        await _logApiError(
          tag: 'SheetChatService.clearAllMessages',
          message: '스프레드시트 ID 미설정으로 삭제 불가',
          error: Exception('spreadsheetId is empty'),
          tags: DebugTags.setForSheetsChat(DebugTags.sheetsChatClear),
        );
        return;
      }

      Future<void> doClearOnce() async {
        state.value = state.value.copyWith(loading: true, error: null);

        final api = await _sheetsApi();
        await _ensureHeaderAndMappingCached(api, sid);

        final rangeToClear = _hasHeaderCached ? '$kChatSheetName!A2:C' : kChatReadRange;

        await api.spreadsheets.values.clear(
          sheets.ClearValuesRequest(),
          sid,
          rangeToClear,
        );

        state.value = const SheetChatState(loading: false, error: null, messages: []);

        // ✅ clear 시 lastSeen도 초기화(빈 문자열로 저장)
        await _saveLastSeen(sid, const _LastSeen(signature: '', rowNumber: 0));
      }

      try {
        await _withAuthRetry<void>(
          tag: 'SheetChatService.clearAllMessages',
          action: doClearOnce,
          userErrorWhenInvalidToken: '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.',
          userErrorWhenFailed: '채팅 삭제 실패',
          extra: <String, dynamic>{
            'sid': sid,
            'clearRange': _hasHeaderCached ? '$kChatSheetName!A2:C' : kChatReadRange,
          },
          logTags: DebugTags.setForSheetsChat(DebugTags.sheetsChatClear),
        );

        _notePollSuccess();
        _reschedulePolling(reason: 'clear_success');
      } catch (_) {
        _reschedulePolling(reason: 'clear_failed');
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 최신 로드 + 델타 판정 + 알림
  // ─────────────────────────────────────────────────────────────

  static const int _incrementalRowBackscanWindow = 20;

  Future<void> _fetchLatest({bool force = false}) async {
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

        await _logApiError(
          tag: 'SheetChatService._fetchLatest',
          message: '스프레드시트 ID 미설정으로 fetch 불가',
          error: Exception('spreadsheetId is empty'),
          extra: <String, dynamic>{'force': force},
          tags: DebugTags.setForSheetsChat(DebugTags.sheetsChatPoll),
        );
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
      await _ensureHeaderAndMappingCached(api, sid);

      // ✅ FIX: canIncremental bool로 promotion 막지 않고, 직접 if 블록에서 null 체크
      final prev = _lastSeen;
      if (!force &&
          !spreadsheetChanged &&
          prev != null &&
          prev.signature.isNotEmpty &&
          prev.rowNumber > 0 &&
          state.value.messages.isNotEmpty) {
        final startRow = math.max(1, prev.rowNumber - _incrementalRowBackscanWindow);
        final ok = await _fetchIncremental(
          api: api,
          sid: sid,
          startRow: startRow,
          prevSig: prev.signature,
        );
        if (ok) {
          _notePollSuccess();
          return;
        }
      }

      await _fetchFull(api: api, sid: sid, force: force || spreadsheetChanged);
      _notePollSuccess();
    }

    try {
      await _withAuthRetry<void>(
        tag: 'SheetChatService._fetchLatest',
        action: doFetchOnce,
        userErrorWhenInvalidToken: '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.',
        userErrorWhenFailed: '채팅 불러오기 실패',
        extra: <String, dynamic>{'force': force},
        logTags: DebugTags.setForSheetsChat(DebugTags.sheetsChatPoll),
      );
    } catch (_) {
      // 내부 처리됨
    } finally {
      _isFetching = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Row parsing (A/B/C 변동 표준화 + legacy 호환)
  // ─────────────────────────────────────────────────────────────

  _ParsedRow? _parseRow({
    required List<Object?> row,
    required int rowNumber,
  }) {
    if (row.isEmpty) return null;

    String cell(int idx) {
      if (idx < 0 || idx >= row.length) return '';
      return (row[idx] ?? '').toString().trim();
    }

    final tsRaw = cell(_colMap.timeIdx);

    String msgRaw = cell(_colMap.messageIdx);
    String idRaw = cell(_colMap.idIdx);

    if (msgRaw.isEmpty) {
      final b = cell(1);
      final c = cell(2);
      if (b.isNotEmpty) {
        msgRaw = b;
      } else if (c.isNotEmpty && idRaw.isEmpty) {
        msgRaw = c;
      }
    }

    if (idRaw.isEmpty) {
      final c = cell(2);
      if (c.isNotEmpty && c != msgRaw) idRaw = c;
    }

    if (msgRaw.isEmpty) return null;

    DateTime? t;
    if (tsRaw.isNotEmpty) t = DateTime.tryParse(tsRaw);

    final signature = (idRaw.isNotEmpty) ? 'id:$idRaw' : '${tsRaw}|${msgRaw}|row$rowNumber';

    return _ParsedRow(
      msg: SheetChatMessage(time: t, text: msgRaw),
      signature: signature,
      rowNumber: rowNumber,
      messageId: idRaw.isNotEmpty ? idRaw : null,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Incremental fetch
  // ─────────────────────────────────────────────────────────────

  Future<bool> _fetchIncremental({
    required sheets.SheetsApi api,
    required String sid,
    required int startRow,
    required String prevSig,
  }) async {
    final range = '$kChatSheetName!A$startRow:C';
    final resp = await api.spreadsheets.values.get(sid, range);
    final rows = resp.values ?? const <List<Object?>>[];

    if (rows.isEmpty) {
      if (state.value.messages.isNotEmpty) {
        state.value = const SheetChatState(loading: false, error: null, messages: []);
        await _saveLastSeen(sid, const _LastSeen(signature: '', rowNumber: 0));
      }
      return true;
    }

    final parsed = <_ParsedRow>[];
    for (int j = 0; j < rows.length; j++) {
      final rowNumber = startRow + j;
      final p = _parseRow(row: rows[j], rowNumber: rowNumber);
      if (p != null) parsed.add(p);
    }

    if (parsed.isEmpty) return true;

    final idx = parsed.indexWhere((e) => e.signature == prevSig);
    if (idx < 0) {
      await _logApiError(
        tag: 'SheetChatService._fetchIncremental',
        message: 'prevSig를 증분 범위에서 찾지 못함 → full fetch fallback',
        error: Exception('prevSig not found in incremental chunk'),
        extra: <String, dynamic>{
          'sid': sid,
          'range': range,
          'startRow': startRow,
          'prevSig': prevSig,
          'parsedCount': parsed.length,
        },
        tags: DebugTags.setForSheetsChat(DebugTags.sheetsChatDelta),
      );
      return false;
    }

    final latest = parsed.last;
    final newRows = (idx + 1 <= parsed.length - 1) ? parsed.sublist(idx + 1) : <_ParsedRow>[];

    if (latest.signature.isNotEmpty && latest.rowNumber > 0) {
      await _saveLastSeen(sid, _LastSeen(signature: latest.signature, rowNumber: latest.rowNumber));
    }

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
          final slice = (nonSelf.length <= n) ? nonSelf : nonSelf.sublist(nonSelf.length - n);
          for (final r in slice) {
            await ChatLocalNotificationService.instance.showChatMessage(
              scopeKey: _scopeKey,
              message: r.msg.text,
            );
          }
        }
      }
    }

    final appended = <SheetChatMessage>[
      ...state.value.messages,
      ...newRows.map((e) => e.msg),
    ];
    final uiMessages = appended.length <= maxMessagesInUi
        ? appended
        : appended.sublist(appended.length - maxMessagesInUi);

    state.value = SheetChatState(loading: false, error: null, messages: uiMessages);
    return true;
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Full fetch
  // ─────────────────────────────────────────────────────────────

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
      final rowNumber = i + 1;
      final p = _parseRow(row: rows[i], rowNumber: rowNumber);
      if (p != null) parsed.add(p);
    }

    final uiMessages = parsed.length <= maxMessagesInUi
        ? parsed.map((e) => e.msg).toList()
        : parsed.sublist(parsed.length - maxMessagesInUi).map((e) => e.msg).toList();

    final latest = parsed.isEmpty ? null : parsed.last;
    final prev = _lastSeen;

    List<_ParsedRow> newRows = const [];

    if (prev == null || prev.signature.isEmpty || prev.rowNumber <= 0) {
      if (latest != null && latest.signature.isNotEmpty) {
        await _saveLastSeen(sid, _LastSeen(signature: latest.signature, rowNumber: latest.rowNumber));
      } else {
        await _saveLastSeen(sid, const _LastSeen(signature: '', rowNumber: 0));
      }
    } else {
      final idx = parsed.indexWhere((e) => e.signature == prev.signature);
      if (idx >= 0) {
        if (idx + 1 <= parsed.length - 1) {
          newRows = parsed.sublist(idx + 1);
        }
        if (latest != null && latest.signature.isNotEmpty && latest.signature != prev.signature) {
          await _saveLastSeen(sid, _LastSeen(signature: latest.signature, rowNumber: latest.rowNumber));
        }
      } else {
        if (latest != null) {
          await _saveLastSeen(sid, _LastSeen(signature: latest.signature, rowNumber: latest.rowNumber));
        } else {
          await _saveLastSeen(sid, const _LastSeen(signature: '', rowNumber: 0));
        }

        await _logApiError(
          tag: 'SheetChatService._fetchFull',
          message: 'prevSig를 찾지 못해 lastSeen을 최신으로 리셋(정렬/삭제/대량편집 가능)',
          error: Exception('prevSig not found'),
          extra: <String, dynamic>{
            'sid': sid,
            'prevSig': prev.signature,
            'latestSig': latest?.signature ?? '',
            'rowCount': rows.length,
            'hasHeaderCached': _hasHeaderCached,
            'force': force,
          },
          tags: DebugTags.setForSheetsChat(DebugTags.sheetsChatDelta),
        );
      }
    }

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
          final slice = (nonSelf.length <= n) ? nonSelf : nonSelf.sublist(nonSelf.length - n);
          for (final r in slice) {
            await ChatLocalNotificationService.instance.showChatMessage(
              scopeKey: _scopeKey,
              message: r.msg.text,
            );
          }
        }
      }
    }

    state.value = SheetChatState(loading: false, error: null, messages: uiMessages);
  }
}
