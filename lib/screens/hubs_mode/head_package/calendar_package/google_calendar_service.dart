// lib/.../google_calendar_service.dart  (경로는 기존 구조에 맞춰주세요)

import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;

// ✅ 중앙 인증 세션만 사용
import 'package:easydev/utils/google_auth_session.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

/// Google Calendar 서비스 (중앙 세션 재사용)
///
/// - 앱 시작 시: `await GoogleAuthSession.instance.init(serverClientId: kWebClientId);`
/// - 본 서비스는 추가 인증 호출 없이 중앙 세션의 AuthClient만 사용
class GoogleCalendarService {
  gcal.CalendarApi? _api;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tCal = 'calendar';
  static const String _tCalService = 'calendar/service';
  static const String _tCalAuth = 'calendar/auth';
  static const String _tCalList = 'calendar/list';
  static const String _tCalCreate = 'calendar/create';
  static const String _tCalUpdate = 'calendar/update';
  static const String _tCalDelete = 'calendar/delete';

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
      // 로깅 실패는 기능에 영향 없도록 무시
    }
  }

  Future<void> _ensureApi() async {
    if (_api != null) return;

    try {
      final client = await GoogleAuthSession.instance.safeClient();
      _api = gcal.CalendarApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService._ensureApi',
        message: 'GoogleAuthSession.safeClient() 또는 CalendarApi 초기화 실패',
        error: e,
        tags: const <String>[_tCal, _tCalService, _tCalAuth],
      );
      rethrow;
    }
  }

  // ===== Read =====
  Future<List<gcal.Event>> listEvents({
    required String calendarId, // 보통 'primary'
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    await _ensureApi();

    final tMin = (timeMin ?? DateTime.now().subtract(const Duration(days: 30))).toUtc();
    final tMax = (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc();

    try {
      final resp = await _api!.events.list(
        calendarId,
        timeMin: tMin,
        timeMax: tMax,
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: maxResults,
      );
      return resp.items ?? <gcal.Event>[];
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.listEvents',
        message: 'Calendar events.list 실패',
        error: e,
        extra: <String, dynamic>{
          'calendarId': calendarId,
          'timeMinUtc': tMin.toIso8601String(),
          'timeMaxUtc': tMax.toIso8601String(),
          'maxResults': maxResults,
        },
        tags: const <String>[_tCal, _tCalService, _tCalList],
      );
      rethrow;
    }
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

    try {
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
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.createEvent',
        message: 'Calendar events.insert 실패',
        error: e,
        extra: <String, dynamic>{
          'calendarId': calendarId,
          'summaryLen': summary.trim().length,
          'hasDescription': (description ?? '').trim().isNotEmpty,
          'allDay': allDay,
          'start': allDay ? DateTime(start.year, start.month, start.day).toIso8601String() : start.toUtc().toIso8601String(),
          'end': allDay ? DateTime(end.year, end.month, end.day).toIso8601String() : end.toUtc().toIso8601String(),
          'colorId': colorId,
        },
        tags: const <String>[_tCal, _tCalService, _tCalCreate],
      );
      rethrow;
    }
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

    try {
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
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.updateEvent',
        message: 'Calendar events.patch 실패',
        error: e,
        extra: <String, dynamic>{
          'calendarId': calendarId,
          'eventId': eventId,
          'hasSummary': summary != null,
          'hasDescription': description != null,
          'hasTimeRange': (start != null && end != null),
          'allDay': allDay,
          'colorIdProvided': colorId != null,
        },
        tags: const <String>[_tCal, _tCalService, _tCalUpdate],
      );
      rethrow;
    }
  }

  // ===== Delete =====
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    await _ensureApi();

    try {
      await _api!.events.delete(calendarId, eventId);
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.deleteEvent',
        message: 'Calendar events.delete 실패',
        error: e,
        extra: <String, dynamic>{
          'calendarId': calendarId,
          'eventId': eventId,
        },
        tags: const <String>[_tCal, _tCalService, _tCalDelete],
      );
      rethrow;
    }
  }

  /// (선택) 명시적 로그아웃/세션 리셋이 필요할 때
  Future<void> signOut() async {
    try {
      await GoogleAuthSession.instance.signOut();
      _api = null;
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.signOut',
        message: 'GoogleAuthSession.signOut 실패',
        error: e,
        tags: const <String>[_tCal, _tCalService, _tCalAuth],
      );
      rethrow;
    }
  }
}
