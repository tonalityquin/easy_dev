import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

/// 구글 캘린더 읽기/쓰기 서비스 (서비스 계정 사용)
class GoogleCalendarService {
  // CRUD를 위해 이벤트 쓰기 스코프 사용
  static const _scopes = [
    gcal.CalendarApi.calendarEventsScope, // 이벤트 읽기/쓰기
    // gcal.CalendarApi.calendarReadonlyScope, // (원하면 추가)
  ];

  final http.Client _base = http.Client();
  auth.AuthClient? _client;
  gcal.CalendarApi? _api;

  Future<void> _ensureAuthClient() async {
    if (_client != null) return;
    // pubspec.yaml 의 assets 경로와 일치해야 합니다.
    final jsonStr =
    await rootBundle.loadString('assets/keys/easydev-97fb6-e31d7e6b30f9.json');
    final Map<String, dynamic> jsonMap = json.decode(jsonStr);

    final creds = auth.ServiceAccountCredentials.fromJson(jsonMap);
    _client = await auth.clientViaServiceAccount(creds, _scopes, baseClient: _base);
    _api = gcal.CalendarApi(_client!);
  }

  // ===== Read =====
  Future<List<gcal.Event>> listEvents({
    required String calendarId,
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    await _ensureAuthClient();
    final resp = await _api!.events.list(
      calendarId,
      timeMin: (timeMin ?? DateTime.now().subtract(const Duration(days: 30))).toUtc(),
      timeMax: (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
      maxResults: maxResults,
    );
    return resp.items ?? <gcal.Event>[];
  }

  // ===== Create =====
  Future<gcal.Event> createEvent({
    required String calendarId,
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? colorId, // "1"~"11" 또는 null
  }) async {
    await _ensureAuthClient();

    final event = gcal.Event()
      ..summary = summary
      ..description = description;

    if (colorId != null && colorId.isNotEmpty) {
      event.colorId = colorId;
    }

    if (allDay) {
      // 날짜만 세팅 (end는 '다음날 0시' 의미로 date만 지정)
      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day);
      event.start = gcal.EventDateTime(date: s);
      event.end   = gcal.EventDateTime(date: e);
    } else {
      event.start = gcal.EventDateTime(dateTime: start.toUtc());
      event.end   = gcal.EventDateTime(dateTime: end.toUtc());
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
    await _ensureAuthClient();

    final patch = gcal.Event();
    if (summary != null) patch.summary = summary;
    if (description != null) patch.description = description;
    if (colorId != null) patch.colorId = colorId;

    // 시간 변경은 start/end 둘 다 들어온 경우에만 적용
    if (start != null && end != null) {
      if (allDay == true) {
        final s = DateTime(start.year, start.month, start.day);
        final e = DateTime(end.year, end.month, end.day);
        patch.start = gcal.EventDateTime(date: s);
        patch.end   = gcal.EventDateTime(date: e);
      } else {
        patch.start = gcal.EventDateTime(dateTime: start.toUtc());
        patch.end   = gcal.EventDateTime(dateTime: end.toUtc());
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
    await _ensureAuthClient();
    await _api!.events.delete(calendarId, eventId);
  }

  void dispose() {
    _client?.close();
    _base.close();
  }
}
