// lib/.../google_calendar_service.dart  (경로는 기존 구조에 맞춰주세요)
import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;

// ✅ 중앙 인증 세션만 사용
import 'package:easydev/utils/google_auth_session.dart';

/// Google Calendar 서비스 (중앙 세션 재사용)
///
/// - 앱 시작 시: `await GoogleAuthSession.instance.init(serverClientId: kWebClientId);`
/// - 본 서비스는 추가 인증 호출 없이 중앙 세션의 AuthClient만 사용
class GoogleCalendarService {
  gcal.CalendarApi? _api;

  Future<void> _ensureApi() async {
    if (_api != null) return;
    final client = await GoogleAuthSession.instance.client();
    _api = gcal.CalendarApi(client);
  }

  // ===== Read =====
  Future<List<gcal.Event>> listEvents({
    required String calendarId, // 보통 'primary'
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    await _ensureApi();
    final resp = await _api!.events.list(
      calendarId,
      timeMin: (timeMin ?? DateTime.now().subtract(const Duration(days: 30)))
          .toUtc(),
      timeMax: (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
      maxResults: maxResults,
    );
    return resp.items ?? <gcal.Event>[];
  }

  // ===== Create =====
  Future<gcal.Event> createEvent({
    required String calendarId, // 'primary'
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? colorId, // "1"~"11" 또는 null
  }) async {
    await _ensureApi();

    final event = gcal.Event()
      ..summary = summary
      ..description = description;

    if (colorId != null && colorId.isNotEmpty) {
      event.colorId = colorId;
    }

    if (allDay) {
      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day);
      event.start = gcal.EventDateTime(date: s);
      event.end = gcal.EventDateTime(date: e);
    } else {
      event.start = gcal.EventDateTime(dateTime: start.toUtc());
      event.end = gcal.EventDateTime(dateTime: end.toUtc());
    }

    final created = await _api!.events.insert(event, calendarId);
    return created;
  }

  // ===== Update (부분 수정 patch 권장) =====
  Future<gcal.Event> updateEvent({
    required String calendarId,
    required String eventId,
    String? summary,
    String? description,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? colorId, // null이면 변경 안 함
  }) async {
    await _ensureApi();

    final patch = gcal.Event();
    if (summary != null) patch.summary = summary;
    if (description != null) patch.description = description;
    if (colorId != null) patch.colorId = colorId;

    if (start != null && end != null) {
      if (allDay == true) {
        final s = DateTime(start.year, start.month, start.day);
        final e = DateTime(end.year, end.month, end.day);
        patch.start = gcal.EventDateTime(date: s);
        patch.end = gcal.EventDateTime(date: e);
      } else {
        patch.start = gcal.EventDateTime(dateTime: start.toUtc());
        patch.end = gcal.EventDateTime(dateTime: end.toUtc());
      }
    }

    final updated = await _api!.events.patch(patch, calendarId, eventId);
    return updated;
  }

  // ===== Delete =====
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    await _ensureApi();
    await _api!.events.delete(calendarId, eventId);
  }

  /// (선택) 명시적 로그아웃/세션 리셋이 필요할 때
  Future<void> signOut() async {
    await GoogleAuthSession.instance.signOut();
    _api = null;
  }
}
