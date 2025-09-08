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

  Future<void> load({String? newCalendarId}) async {
    if (newCalendarId != null) calendarId = newCalendarId.trim();
    if (calendarId.isEmpty) {
      error = '캘린더 ID를 입력하세요.';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      events = await _service.listEvents(calendarId: calendarId);
    } catch (e) {
      error = '불러오기 실패: $e';
      events = [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
