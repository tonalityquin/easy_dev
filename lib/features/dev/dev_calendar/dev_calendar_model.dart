
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;


import 'dev_google_calendar_service.dart';

class DevCalendarModel extends ChangeNotifier {
  final DevGoogleCalendarService _service;

  DevCalendarModel(this._service);

  String calendarId = '';
  bool loading = false;
  String? error;
  List<gcal.Event> events = [];

  
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

  
  
  
  
  Future<void> loadRange({
    required DateTime timeMin,
    required DateTime timeMax, 
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
      
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  
  Future<gcal.Event?> create({
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? colorId, 
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
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  
  Future<gcal.Event?> update({
    required String eventId,
    String? summary,
    String? description,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? colorId, 
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
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  
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
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  

  void _sortEvents() {
    events.sort((a, b) {
      final sa = a.start?.dateTime ?? a.start?.date ?? DateTime(1900);
      final sb = b.start?.dateTime ?? b.start?.date ?? DateTime(1900);
      return sa.compareTo(sb);
    });
  }

  List<gcal.Event> _filterByRange(
    List<gcal.Event> source,
    DateTime min, 
    DateTime max, 
  ) {
    bool overlaps(gcal.Event e) {
      final range = _eventRangeLocal(e);
      if (range == null) return false;
      final start = range.$1;
      final end = range.$2;
      
      return start.isBefore(max) && end.isAfter(min);
    }

    final filtered = source.where(overlaps).toList();
    return filtered;
  }

  
  
  
  (DateTime, DateTime)? _eventRangeLocal(gcal.Event e) {
    if (e.start == null) return null;

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
  }
}
