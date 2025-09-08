import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'google_calendar_service.dart';

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

  // ====== Create (allDay 지원 + colorId 지원) ======
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
    try {
      final created = await _service.createEvent(
        calendarId: calendarId,
        summary: summary,
        description: description,
        start: start,
        end: end,
        allDay: allDay,
        colorId: colorId,
      );
      events.add(created);
      _sortEvents();
      notifyListeners();
      return created;
    } catch (e) {
      error = '생성 실패: $e';
      notifyListeners();
      return null;
    }
  }

  // ====== Update (부분 수정 + colorId 지원) ======
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
    try {
      final updated = await _service.updateEvent(
        calendarId: calendarId,
        eventId: eventId,
        summary: summary,
        description: description,
        start: start,
        end: end,
        allDay: allDay,
        colorId: colorId,
      );
      final i = events.indexWhere((e) => e.id == eventId);
      if (i != -1) {
        events[i] = updated;
        _sortEvents();
      }
      notifyListeners();
      return updated;
    } catch (e) {
      error = '수정 실패: $e';
      notifyListeners();
      return null;
    }
  }

  // ====== Delete ======
  Future<bool> delete({required String eventId}) async {
    if (calendarId.isEmpty) {
      error = '먼저 캘린더를 불러오세요.';
      notifyListeners();
      return false;
    }
    try {
      await _service.deleteEvent(calendarId: calendarId, eventId: eventId);
      events.removeWhere((e) => e.id == eventId);
      notifyListeners();
      return true;
    } catch (e) {
      error = '삭제 실패: $e';
      notifyListeners();
      return false;
    }
  }

  void _sortEvents() {
    events.sort((a, b) {
      final sa = a.start?.dateTime ?? a.start?.date ?? DateTime(1900);
      final sb = b.start?.dateTime ?? b.start?.date ?? DateTime(1900);
      return sa!.compareTo(sb!);
    });
  }
}
