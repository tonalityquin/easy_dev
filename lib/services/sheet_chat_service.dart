import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/google_auth_session.dart';

/// ✅ Header에서 저장한 "스프레드시트 ID" SharedPreferences 키와 동일해야 함.
const String kSharedSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

/// ✅ (중요) 채팅 시트명 고정: chat
const String kChatSheetName = 'chat';

/// ✅ 채팅 Range: 하위호환(구형 C열까지 포함)을 위해 A:C로 읽음
const String kChatReadRange = '$kChatSheetName!A:C';

/// ✅ 채팅 시트의 헤더 감지용(1행 확인)
const String kChatHeaderProbeRange = '$kChatSheetName!A1:C1';

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

/// ✅ Google Sheets 기반 공개(익명) 채팅 서비스
/// - Header에서 저장한 Spreadsheet ID를 SharedPreferences에서 읽음
/// - `chat` 시트에 [timestamp, message] 형태로 기록
/// - polling으로 주기적 갱신(실시간 스트림 대체)
///
/// ✅ 하위호환:
/// - 과거 포맷 [timestamp, roomId, message] (A,B,C) 존재 시 message는 C를 사용
///
/// ✅ 중요 변경점:
/// - 기존 `values.append()`는 "시트가 기억하는 마지막 사용영역" 다음에 계속 붙는 경우가 있어,
///   사용자가 시트에서 값을 삭제해도 다음 행부터 입력되는 문제가 발생할 수 있음.
/// - 이를 방지하기 위해, 전송 시 "첫 빈 행"을 찾아 해당 행에 `values.update()`로 기록하도록 변경.
class SheetChatService {
  SheetChatService._();

  static final SheetChatService instance = SheetChatService._();

  /// UI는 이 상태만 구독하면 됨
  final ValueNotifier<SheetChatState> state =
  ValueNotifier<SheetChatState>(SheetChatState.empty);

  // (이제 시트 내부 roomId는 쓰지 않지만)
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

  /// 서비스 시작(여러 번 호출되어도 안전)
  /// - scopeKey는 "영역 전환 시 재시작" 용도로만 사용
  Future<void> start(String scopeKey) async {
    final key = scopeKey.trim();

    // 같은 scope이면 idempotent
    final sameScope = _scopeKey == key;
    _scopeKey = key;

    if (sameScope && _timer != null) return;

    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _fetchLatest());

    // 즉시 1회 로드
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

  /// ✅ 헤더 유무 판정(휴리스틱)
  /// - A1이 timestamp로 파싱되지 않고,
  /// - 헤더스러운 키워드(time/date/timestamp/message)가 있으면 헤더로 간주
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
      if (dt != null) return false; // A1이 timestamp면 헤더 아님(데이터 1행)

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

  /// ✅ A열 기준 "첫 빈 행" 찾기
  /// - 헤더가 있으면 2행부터, 없으면 1행부터 검색
  Future<int> _findFirstEmptyRowIndex(sheets.SheetsApi api, String sid) async {
    final hasHeader = await _hasHeaderRow(api, sid);
    final startRow = hasHeader ? 2 : 1;

    // A열 전체를 읽어 첫 빈 행을 찾음
    // (데이터가 커질 경우 A1:A5000 같은 제한으로 바꾸는 것도 가능)
    final colResp = await api.spreadsheets.values.get(sid, '$kChatSheetName!A:A');
    final rows = colResp.values ?? const <List<Object?>>[];

    // rows는 1행부터 순서대로 반환
    for (int i = startRow - 1; i < rows.length; i++) {
      final row = rows[i];
      final a = row.isNotEmpty ? (row[0] ?? '').toString().trim() : '';
      if (a.isEmpty) {
        return i + 1; // 0-based → 1-based row index
      }
    }

    // 빈 행이 없으면 마지막 다음 행
    final next = rows.length + 1;
    return next < startRow ? startRow : next;
  }

  Future<bool> _isRowEmptyAB(sheets.SheetsApi api, String sid, int rowIndex) async {
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

  /// ✅ 메시지 전송: "첫 빈 행"에 update로 기록
  /// - 작성자 없음(익명 통일)
  /// - row(신형): [timestamp(ISO UTC), message]
  ///
  /// ✅ 변경 효과:
  /// - 사용자가 스프레드시트에서 값을 삭제하더라도,
  ///   다음 전송이 "그 다음 행"으로 밀리지 않고 "첫 빈 행"부터 다시 채워짐.
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

      try {
        final api = await _sheetsApi();
        final nowUtc = DateTime.now().toUtc().toIso8601String();

        final vr = sheets.ValueRange(values: [
          [nowUtc, msg],
        ]);

        // 동시 전송(다중 기기/다중 사용자) 경합을 완화하기 위한 재시도
        const int maxRetry = 6;
        bool wrote = false;

        for (int attempt = 0; attempt < maxRetry; attempt++) {
          final rowIndex = await _findFirstEmptyRowIndex(api, spreadsheetId);

          // 선택한 행이 진짜 비어있는지 A:B 재확인(경합 완화)
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
          // 매우 드문 케이스(지속 경합 등): 실패로 끝내기보다 에러 표기
          state.value = state.value.copyWith(
            loading: false,
            error: '채팅 전송 실패: 저장 위치(빈 행) 확보에 실패했습니다. 잠시 후 다시 시도하세요.',
          );
          return;
        }

        // 전송 직후 즉시 반영
        await _fetchLatest(force: true);
      } catch (e) {
        final msg = GoogleAuthSession.isInvalidTokenError(e)
            ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
            : '채팅 전송 실패: $e';

        state.value = state.value.copyWith(loading: false, error: msg);
      }
    });
  }

  /// ✅ 채팅 시트 내용 전부 삭제
  /// - 기본: 헤더가 있으면 2행부터, 없으면 전체(A:C) 삭제
  ///
  /// 참고:
  /// - values.clear는 "값만" 지우므로, 예전 append 기준에서는 다음 행으로 밀리는 현상이 있을 수 있었음.
  /// - 본 서비스는 sendMessage가 update 기반이므로, clear 후에도 첫 빈 행부터 다시 기록됨.
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

      try {
        state.value = state.value.copyWith(loading: true, error: null);

        final api = await _sheetsApi();
        final hasHeader = await _hasHeaderRow(api, sid);

        final rangeToClear = hasHeader ? '$kChatSheetName!A2:C' : kChatReadRange;

        await api.spreadsheets.values.clear(
          sheets.ClearValuesRequest(),
          sid,
          rangeToClear,
        );

        // UI 즉시 반영
        state.value = const SheetChatState(loading: false, error: null, messages: []);
      } catch (e) {
        final msg = GoogleAuthSession.isInvalidTokenError(e)
            ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
            : '채팅 삭제 실패: $e';

        state.value = state.value.copyWith(loading: false, error: msg);
      }
    });
  }

  /// ✅ 최신 메시지/목록 로드 (polling)
  Future<void> _fetchLatest({bool force = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
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

      if (force || spreadsheetChanged || state.value.messages.isEmpty) {
        state.value = state.value.copyWith(loading: true, error: null);
      }

      final api = await _sheetsApi();
      final resp = await api.spreadsheets.values.get(sid, kChatReadRange);

      final rows = resp.values ?? const <List<Object?>>[];
      final parsed = <SheetChatMessage>[];

      for (final row in rows) {
        // 신형 기대: [timestamp, message]
        // 구형 기대: [timestamp, roomId, message]
        final tsRaw = row.isNotEmpty ? (row[0] ?? '').toString().trim() : '';

        String msgRaw = '';
        if (row.length >= 3) {
          // 구형: C열이 메시지
          msgRaw = (row[2] ?? '').toString().trim();
        } else if (row.length >= 2) {
          // 신형: B열이 메시지
          msgRaw = (row[1] ?? '').toString().trim();
        }

        if (msgRaw.isEmpty) continue;

        DateTime? t;
        if (tsRaw.isNotEmpty) {
          t = DateTime.tryParse(tsRaw);
        }

        parsed.add(SheetChatMessage(time: t, text: msgRaw));
      }

      final trimmed = parsed.length <= maxMessagesInUi
          ? parsed
          : parsed.sublist(parsed.length - maxMessagesInUi);

      state.value = SheetChatState(
        loading: false,
        error: null,
        messages: trimmed,
      );
    } catch (e) {
      final msg = GoogleAuthSession.isInvalidTokenError(e)
          ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
          : '채팅 불러오기 실패: $e';

      state.value = state.value.copyWith(loading: false, error: msg);
    } finally {
      _isFetching = false;
    }
  }
}
