import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

// ✅ 중앙 인증 세션(v7 대응)을 통해 단 한 번 로그인한 세션을 재사용합니다.
//   이 파일 안에서는 GoogleSignIn / authorizeScopes / authenticate 등을 호출하지 않습니다.
import 'package:easydev/utils/google_auth_session.dart';

/// 개발용 Google Calendar 서비스
///
/// - 최초 앱 실행 시 `GoogleAuthSession.instance.init(...)`이 한 번만 수행되어야 합니다.
/// - 이후 이 서비스는 `AuthClient`를 중앙 세션에서 받아와 API 인스턴스를 구성하고 재사용합니다.
/// - 메서드 호출 중 401/권한 오류가 감지되면 `refreshIfNeeded()` 후 1회 재시도하는 패턴을 권장합니다.
class DevGoogleCalendarService {
  auth.AuthClient? _client;
  gcal.CalendarApi? _api;

  // ===================== Internal =====================

  Future<void> _ensureApi() async {
    if (_api != null) return;
    _client = await GoogleAuthSession.instance.safeClient();
    _api = gcal.CalendarApi(_client!);
  }

  // 401 등의 오류가 발생한 경우 한 번 재구성 후 재시도할 때 사용
  Future<T> _withReauth<T>(Future<T> Function() op) async {
    try {
      await _ensureApi();
      return await op();
    } catch (e) {
      // 간단 재시도 정책: 한 번 세션 재구성 후 재시도
      await GoogleAuthSession.instance.refreshIfNeeded();
      _api = null;
      await _ensureApi();
      return await op();
    }
  }

  // ===================== Read =====================

  /// 기간 내 이벤트를 정렬(시작시간 오름차순)하여 반환합니다.
  ///
  /// [calendarId] 보통 'primary'
  /// [timeMin] 기본: 오늘 기준 30일 전, [timeMax] 기본: 오늘 기준 60일 후
  /// [maxResults] 기본 100
  Future<List<gcal.Event>> listEvents({
    required String calendarId,
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    return _withReauth(() async {
      final api = _api!;
      final resp = await api.events.list(
        calendarId,
        timeMin: (timeMin ?? DateTime.now().subtract(const Duration(days: 30)))
            .toUtc(),
        timeMax:
        (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: maxResults,
      );
      return resp.items ?? <gcal.Event>[];
    });
  }

  // ===================== Create =====================

  /// 단건 이벤트 생성
  ///
  /// [allDay]가 true면 종일 이벤트로 생성합니다.
  /// [colorId]는 Calendar 색상 ID를 그대로 사용합니다(선택).
  Future<gcal.Event> createEvent({
    required String calendarId, // 'primary'
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? colorId,
  }) async {
    return _withReauth(() async {
      final api = _api!;

      final event = gcal.Event()
        ..summary = summary
        ..description = description;

      if (colorId != null && colorId.isNotEmpty) {
        event.colorId = colorId;
      }

      if (allDay) {
        // Google Calendar 종일 이벤트는 date 를 사용합니다.
        final s = DateTime(start.year, start.month, start.day);
        // 주의: 서버는 end.date를 "exclusive"로 처리합니다. 기존 코드 호환을 위해 그대로 둡니다.
        final e = DateTime(end.year, end.month, end.day);
        event.start = gcal.EventDateTime(date: s);
        event.end = gcal.EventDateTime(date: e);
      } else {
        event.start = gcal.EventDateTime(dateTime: start.toUtc());
        event.end = gcal.EventDateTime(dateTime: end.toUtc());
      }

      final created = await api.events.insert(event, calendarId);
      return created;
    });
  }

  // ===================== Update (patch 권장) =====================

  /// 이벤트 부분 수정 (PATCH)
  ///
  /// 전달된 필드만 변경됩니다.
  Future<gcal.Event> updateEvent({
    required String calendarId,
    required String eventId,
    String? summary,
    String? description,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? colorId,
  }) async {
    return _withReauth(() async {
      final api = _api!;

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

      final updated = await api.events.patch(patch, calendarId, eventId);
      return updated;
    });
  }

  // ===================== Delete =====================

  /// 이벤트 삭제
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    return _withReauth(() async {
      final api = _api!;
      await api.events.delete(calendarId, eventId);
    });
  }

  // ===================== Session Control =====================

  /// (선택) 명시적 로그아웃/세션 초기화가 필요할 때
  Future<void> signOut() async {
    await GoogleAuthSession.instance.signOut();
    _client = null;
    _api = null;
  }
}
