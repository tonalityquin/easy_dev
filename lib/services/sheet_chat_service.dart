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

/// ✅ 채팅 Append Range: 신형 포맷(A:B)에 append
const String kChatAppendRange = '$kChatSheetName!A:B';

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
/// - `chat` 시트에 [timestamp, message] 형태로 append
/// - polling으로 주기적 갱신(실시간 스트림 대체)
///
/// ✅ 하위호환:
/// - 과거 포맷 [timestamp, roomId, message] (A,B,C) 존재 시 message는 C를 사용
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

  /// ✅ 메시지 전송: chat 시트에 append
  /// - 작성자 없음(익명 통일)
  /// - row(신형): [timestamp(ISO UTC), message]
  Future<void> sendMessage(String message) async {
    final msg = message.trim();
    if (msg.isEmpty) return;

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

      await api.spreadsheets.values.append(
        vr,
        spreadsheetId,
        kChatAppendRange,
        valueInputOption: 'RAW',
        insertDataOption: 'INSERT_ROWS',
      );

      // 전송 직후 즉시 반영
      await _fetchLatest(force: true);
    } catch (e) {
      final msg = GoogleAuthSession.isInvalidTokenError(e)
          ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
          : '채팅 전송 실패: $e';

      state.value = state.value.copyWith(loading: false, error: msg);
    }
  }

  /// ✅ (신규) 채팅 시트 내용 전부 삭제
  /// - 메일 전송 후 호출 용도
  /// - 기본: 헤더가 있으면 2행부터, 없으면 전체(A:C) 삭제
  Future<void> clearAllMessages({String? spreadsheetIdOverride}) async {
    // polling fetch와 충돌 가능성을 줄이기 위해 잠깐 막음
    if (_isFetching) {
      // 너무 공격적으로 return하면 삭제가 안 될 수 있어, 여기선 그냥 진행하지 않고 한 번 더 시도하도록 호출측에서 재호출 가능
      // 요구사항상 "전송 후 삭제"이므로, 여기서는 진행하도록 _isFetching을 무시하지 않고 계속 수행
    }

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

      // 1) 헤더 유무 휴리스틱 판정
      bool hasHeader = false;
      try {
        final headResp = await api.spreadsheets.values.get(sid, kChatHeaderProbeRange);
        final headRow = (headResp.values != null && headResp.values!.isNotEmpty)
            ? headResp.values!.first
            : null;

        if (headRow != null && headRow.isNotEmpty) {
          final a = (headRow[0] ?? '').toString().trim();
          final b = (headRow.length > 1 ? (headRow[1] ?? '') : '').toString().trim();
          final c = (headRow.length > 2 ? (headRow[2] ?? '') : '').toString().trim();

          final dt = DateTime.tryParse(a);

          // timestamp가 DateTime으로 파싱 안 되고,
          // 헤더스러운 키워드가 있으면 헤더로 간주
          final aL = a.toLowerCase();
          final bL = b.toLowerCase();
          final cL = c.toLowerCase();

          if (dt == null) {
            if (aL.contains('time') ||
                aL.contains('date') ||
                aL.contains('timestamp') ||
                bL.contains('message') ||
                cL.contains('message')) {
              hasHeader = true;
            }
          }
        }
      } catch (_) {
        // probe 실패 시 헤더 없다고 보고 전체 삭제(안전하게 비우는 쪽)
        hasHeader = false;
      }

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
