// lib/screens/head_package/calendar_package/calendar_model.dart
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

// 같은 폴더라면 아래 상대경로 유지, 폴더 구조가 다르면 경로만 수정하세요.
import './google_calendar_service.dart';

class CalendarModel extends ChangeNotifier {
  final GoogleCalendarService _service;

  CalendarModel(this._service);

  String calendarId = '';
  bool loading = false;
  String? error;
  List<gcal.Event> events = [];

  // URL 전체를 붙여넣어도 src=에서 캘린더 ID를 뽑아내는 정규화
  String? _normalizeCalendarId(String raw) {
    if (raw.isEmpty) return null;
    var s = raw.trim();

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
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ===== NEW: 특정 기간(예: 월 범위)만 로드하여 events를 교체 =====
  // 현재 GoogleCalendarService.listEvents(calendarId: ...) 시그니처만 있다고 가정하고,
  // 일단 전체를 받아 클라이언트에서 [timeMin, timeMax)로 필터링합니다.
  // (효율을 높이려면 service에 timeMin/timeMax 지원을 추가해 서버 측에서 기간 조회하세요.)
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
      final all = await _service.listEvents(calendarId: calendarId);
      events = _filterByRange(all, timeMin, timeMax);
      _sortEvents();
    } catch (e) {
      error = '기간 로드 실패: $e';
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

      // ✅ 생성 후 서버 기준으로 다시 목록 불러오기
      await refresh();
      return null; // 목록을 새로 불러오므로 단일 반환은 사용하지 않아도 됨
    } catch (e) {
      error = '생성 실패: $e';
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
      // ✅ 반드시 description을 patch에 포함시키기 위해
      //    description이 null이면 현재 이벤트의 description(또는 '')를 사용
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
        // ← 항상 non-null로 전달하여 patch에 포함
        start: start,
        end: end,
        allDay: allDay,
        colorId: colorId,
      );

      // ✅ 수정 후 서버 기준으로 다시 목록 불러오기
      await refresh();
      return null;
    } catch (e) {
      error = '수정 실패: $e';
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

      // ✅ 삭제 후 서버 기준으로 다시 목록 불러오기
      await refresh();
      return true;
    } catch (e) {
      error = '삭제 실패: $e';
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

    final filtered = source.where(overlaps).toList();
    return filtered;
  }

  /// 이벤트의 로컬시간 기준 [start, end)를 계산
  /// - 종일: start = start.date 00:00, end = end.date 00:00 (Google은 end.date가 exclusive)
  /// - 시간제: start = start.dateTime, end = end.dateTime (end가 null이면 start + 1h 가정)
  (DateTime, DateTime)? _eventRangeLocal(gcal.Event e) {
    if (e.start == null) return null;

    if (e.start?.date != null) {
      // 종일
      final s = e.start!.date!;
      // end.date는 다음날 00:00 (exclusive)
      final ed = e.end?.date ?? s.add(const Duration(days: 1));
      final start = DateTime(s.year, s.month, s.day);
      final end = DateTime(ed.year, ed.month, ed.day);
      return (start, end);
    } else {
      // 시간제
      final sdt = e.start?.dateTime?.toLocal();
      final edt = e.end?.dateTime?.toLocal();
      if (sdt == null) return null;
      final end = edt ?? sdt.add(const Duration(hours: 1));
      return (sdt, end);
    }
  }
}
