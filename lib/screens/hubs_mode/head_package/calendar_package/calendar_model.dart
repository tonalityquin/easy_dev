// lib/screens/head_package/calendar_package/calendar_model.dart
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

// 같은 폴더라면 아래 상대경로 유지, 폴더 구조가 다르면 경로만 수정하세요.
import './google_calendar_service.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

class CalendarModel extends ChangeNotifier {
  final GoogleCalendarService _service;

  CalendarModel(this._service);

  String calendarId = '';
  bool loading = false;
  String? error;
  List<gcal.Event> events = [];

  // ---- progress 파생상태 유틸 (위젯 쪽에서 공용으로 쓰기 좋게 제공) ----
  static final RegExp progressTag =
  RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false);

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tCal = 'calendar';
  static const String _tCalModel = 'calendar/model';
  static const String _tCalService = 'calendar/service';
  static const String _tCalLoad = 'calendar/load';
  static const String _tCalRange = 'calendar/load_range';
  static const String _tCalCrud = 'calendar/crud';
  static const String _tCalParse = 'calendar/parse';

  Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {
      // 로깅 실패는 모델 동작에 영향 없도록 무시
    }
  }

  Map<String, dynamic> _ctxBase() {
    return <String, dynamic>{
      'calendarId': calendarId,
      'eventsCount': events.length,
      'loading': loading,
    };
  }

  /// description에 [progress:0|100]이 있으면 0/100 반환, 없으면 0
  static int progressOfEvent(gcal.Event e) {
    final m = progressTag.firstMatch(e.description ?? '');
    if (m == null) return 0;
    final v = int.tryParse(m.group(1) ?? '0') ?? 0;
    return v == 100 ? 100 : 0;
  }

  /// description에 [progress:x]를 삽입/치환하여 반환 (x는 0 또는 100)
  static String setProgressTag(String? description, int progress) {
    final val = (progress == 100) ? 100 : 0;
    final base = (description ?? '').trimRight();
    if (progressTag.hasMatch(base)) {
      return base.replaceAllMapped(progressTag, (_) => '[progress:$val]');
    }
    if (base.isEmpty) return '[progress:$val]';
    return '$base\n[progress:$val]';
  }

  // URL 전체를 붙여넣어도 src=에서 캘린더 ID를 뽑아내는 정규화
  String? _normalizeCalendarId(String raw) {
    if (raw.isEmpty) return null;
    var s = raw.trim();

    try {
      if (s.startsWith('http')) {
        final uri = Uri.tryParse(s);
        final src = uri?.queryParameters['src'];
        if (src != null && src.isNotEmpty) return Uri.decodeComponent(src);
        final idx = s.indexOf('src=');
        if (idx != -1) {
          var tail = s.substring(idx + 4);
          final amp = tail.indexOf('&');
          if (amp != -1) tail = tail.substring(0, amp);
          return Uri.decodeComponent(tail);
        }
      }

      if (s.contains('&')) s = s.split('&').first;
      return Uri.decodeComponent(s);
    } catch (e) {
      // normalize는 UI 입력 보정 성격이 강해서, 실패를 조용히 처리하되 로그는 남김
      _logApiError(
        tag: 'CalendarModel._normalizeCalendarId',
        message: '캘린더 ID 정규화 실패',
        error: e,
        extra: <String, dynamic>{
          'rawLen': raw.length,
          'rawPrefix': raw.length > 24 ? raw.substring(0, 24) : raw,
        },
        tags: const <String>[_tCal, _tCalModel, _tCalParse],
      );
      return null;
    }
  }

  /// 서버에서 최신 이벤트 목록을 다시 불러옵니다.
  Future<void> refresh() async {
    if (calendarId.isEmpty) return;

    try {
      loading = true;
      error = null;
      notifyListeners();

      events = await _service.listEvents(calendarId: calendarId);
      _sortEvents();
    } catch (e) {
      error = '새로고침 실패: $e';

      await _logApiError(
        tag: 'CalendarModel.refresh',
        message: '이벤트 새로고침(listEvents) 실패',
        error: e,
        extra: _ctxBase(),
        tags: const <String>[_tCal, _tCalModel, _tCalService, _tCalLoad],
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> load({String? newCalendarId}) async {
    final raw = (newCalendarId ?? calendarId).trim();
    final normalized = _normalizeCalendarId(raw);
    if (normalized == null || normalized.isEmpty) {
      error = '캘린더 ID를 입력하세요.';
      notifyListeners();
      return;
    }
    calendarId = normalized;

    loading = true;
    error = null;
    notifyListeners();

    try {
      events = await _service.listEvents(calendarId: calendarId);
      _sortEvents();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('status: 404')) {
        error = '404: 캘린더가 없거나 접근 권한이 없습니다.\n'
            '- ID 확인 및 서비스 계정 공유(보기/편집 권한) 확인';
      } else if (msg.contains('status: 403')) {
        error = '403: 권한 오류입니다. 서비스 계정 권한을 확인하세요.';
      } else {
        error = '불러오기 실패: $msg';
      }
      events = [];

      await _logApiError(
        tag: 'CalendarModel.load',
        message: '캘린더 이벤트 불러오기(listEvents) 실패',
        error: e,
        extra: <String, dynamic>{
          ..._ctxBase(),
          'inputRawLen': raw.length,
          'calendarIdNormalized': calendarId,
        },
        tags: const <String>[_tCal, _tCalModel, _tCalService, _tCalLoad],
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ===== 특정 기간만 로드 =====
  // 현재 GoogleCalendarService.listEvents(calendarId: ...)가 timeMin/timeMax를 지원하므로
  // 서버 측 기간 조회로 효율화하여 listEvents를 호출합니다.
  Future<void> loadRange({
    required DateTime timeMin,
    required DateTime timeMax, // exclusive
  }) async {
    if (calendarId.isEmpty) {
      error = '먼저 캘린더를 불러오세요.';
      notifyListeners();
      return;
    }

    loading = true;
    error = null;
    notifyListeners();

    try {
      final ranged = await _service.listEvents(
        calendarId: calendarId,
        timeMin: timeMin,
        timeMax: timeMax,
      );

      // 안전망: 혹시 서버가 넓게 주더라도 클라이언트에서 한 번 더 범위 필터
      events = _filterByRange(ranged, timeMin, timeMax);
      _sortEvents();
    } catch (e) {
      error = '기간 로드 실패: $e';

      await _logApiError(
        tag: 'CalendarModel.loadRange',
        message: '기간 로드(listEvents timeMin/timeMax) 실패',
        error: e,
        extra: <String, dynamic>{
          ..._ctxBase(),
          'timeMin': timeMin.toIso8601String(),
          'timeMaxExclusive': timeMax.toIso8601String(),
        },
        tags: const <String>[_tCal, _tCalModel, _tCalService, _tCalRange],
      );
      // 실패 시 기존 events 유지
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ===== Create (allDay + colorId 지원) =====
  Future<gcal.Event?> create({
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? colorId, // "1"~"11" 또는 null
  }) async {
    if (calendarId.isEmpty) {
      error = '먼저 캘린더를 불러오세요.';
      notifyListeners();
      return null;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _service.createEvent(
        calendarId: calendarId,
        summary: summary,
        // 생성 시 description이 비어도 서버에 반영되도록 빈문자라도 전달
        description: description ?? '',
        start: start,
        end: end,
        allDay: allDay,
        colorId: colorId,
      );

      await refresh();
      return null;
    } catch (e) {
      error = '생성 실패: $e';

      await _logApiError(
        tag: 'CalendarModel.create',
        message: '이벤트 생성(createEvent) 실패',
        error: e,
        extra: <String, dynamic>{
          ..._ctxBase(),
          'summaryLen': summary.trim().length,
          'hasDescription': (description ?? '').trim().isNotEmpty,
          'allDay': allDay,
          'colorIdProvided': (colorId ?? '').trim().isNotEmpty,
        },
        tags: const <String>[_tCal, _tCalModel, _tCalService, _tCalCrud],
      );

      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ===== Update (부분 수정 + colorId 지원) =====
  Future<gcal.Event?> update({
    required String eventId,
    String? summary,
    String? description,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? colorId, // null이면 변경 안 함
  }) async {
    if (calendarId.isEmpty) {
      error = '먼저 캘린더를 불러오세요.';
      notifyListeners();
      return null;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      final current = events.firstWhere(
            (e) => e.id == eventId,
        orElse: () => gcal.Event()..description = '',
      );
      final descToSend = (description != null) ? description : (current.description ?? '');

      await _service.updateEvent(
        calendarId: calendarId,
        eventId: eventId,
        summary: summary,
        description: descToSend,
        start: start,
        end: end,
        allDay: allDay,
        colorId: colorId,
      );

      await refresh();
      return null;
    } catch (e) {
      error = '수정 실패: $e';

      await _logApiError(
        tag: 'CalendarModel.update',
        message: '이벤트 수정(updateEvent) 실패',
        error: e,
        extra: <String, dynamic>{
          ..._ctxBase(),
          'eventId': eventId,
          'hasSummary': summary != null,
          'hasDescription': description != null,
          'hasTimeRange': (start != null && end != null),
          'allDay': allDay,
          'colorIdProvided': colorId != null,
        },
        tags: const <String>[_tCal, _tCalModel, _tCalService, _tCalCrud],
      );

      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ===== Delete =====
  Future<bool> delete({required String eventId}) async {
    if (calendarId.isEmpty) {
      error = '먼저 캘린더를 불러오세요.';
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _service.deleteEvent(calendarId: calendarId, eventId: eventId);
      await refresh();
      return true;
    } catch (e) {
      error = '삭제 실패: $e';

      await _logApiError(
        tag: 'CalendarModel.delete',
        message: '이벤트 삭제(deleteEvent) 실패',
        error: e,
        extra: <String, dynamic>{
          ..._ctxBase(),
          'eventId': eventId,
        },
        tags: const <String>[_tCal, _tCalModel, _tCalService, _tCalCrud],
      );

      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ===== Helpers =====

  void _sortEvents() {
    events.sort((a, b) {
      final sa = a.start?.dateTime ?? a.start?.date ?? DateTime(1900);
      final sb = b.start?.dateTime ?? b.start?.date ?? DateTime(1900);
      return sa.compareTo(sb);
    });
  }

  List<gcal.Event> _filterByRange(
      List<gcal.Event> source,
      DateTime min, // inclusive
      DateTime max, // exclusive
      ) {
    bool overlaps(gcal.Event e) {
      final range = _eventRangeLocal(e);
      if (range == null) return false;
      final start = range.$1;
      final end = range.$2;
      // [start, end) 와 [min, max) 가 겹치면 true
      return start.isBefore(max) && end.isAfter(min);
    }

    return source.where(overlaps).toList();
  }

  /// 이벤트의 로컬시간 기준 [start, end)를 계산
  /// - 종일: start = start.date 00:00, end = end.date 00:00 (Google은 end.date가 exclusive)
  /// - 시간제: start = start.dateTime, end = end.dateTime (end가 null이면 start + 1h 가정)
  (DateTime, DateTime)? _eventRangeLocal(gcal.Event e) {
    if (e.start == null) return null;

    try {
      if (e.start?.date != null) {
        final s = e.start!.date!;
        final ed = e.end?.date ?? s.add(const Duration(days: 1));
        final start = DateTime(s.year, s.month, s.day);
        final end = DateTime(ed.year, ed.month, ed.day);
        return (start, end);
      } else {
        final sdt = e.start?.dateTime?.toLocal();
        final edt = e.end?.dateTime?.toLocal();
        if (sdt == null) return null;
        final end = edt ?? sdt.add(const Duration(hours: 1));
        return (sdt, end);
      }
    } catch (e2) {
      _logApiError(
        tag: 'CalendarModel._eventRangeLocal',
        message: '이벤트 시간 범위 파싱 실패',
        error: e2,
        extra: <String, dynamic>{
          'eventId': e.id ?? '',
          'hasStartDate': e.start?.date != null,
          'hasStartDateTime': e.start?.dateTime != null,
          'hasEndDate': e.end?.date != null,
          'hasEndDateTime': e.end?.dateTime != null,
        },
        tags: const <String>[_tCal, _tCalModel, _tCalParse],
      );
      return null;
    }
  }
}
