import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

/// ✅ 웹 “클라이언트 ID”(Web Application)
const String kWebClientId =
    '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

class DevGoogleCalendarService {
  // R/W가 필요하면 calendarEventsScope 권장
  static const _scopes = <String>[
    gcal.CalendarApi.calendarEventsScope,
  ];

  bool _initialized = false;
  auth.AuthClient? _client;
  gcal.CalendarApi? _api;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // ✅ Android: serverClientId로 웹 클라ID 지정(28444 방지)
    await GoogleSignIn.instance.initialize(serverClientId: kWebClientId);
    _initialized = true;
  }

  Future<GoogleSignInAccount> _waitForSignInEvent() async {
    final signIn = GoogleSignIn.instance;
    final completer = Completer<GoogleSignInAccount>();
    late final StreamSubscription sub;
    sub = signIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          if (!completer.isCompleted) completer.complete(event.user);
        case GoogleSignInAuthenticationEventSignOut():
          break;
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    try {
      try {
        await signIn.attemptLightweightAuthentication();
      } catch (_) {}
      if (signIn.supportsAuthenticate()) {
        // UI 인증은 확실히 기다림
        await signIn.authenticate();
      }
      final user = await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw Exception('Google 로그인 응답 시간 초과'),
      );
      return user;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _ensureAuthClient() async {
    if (_client != null && _api != null) return;

    await _ensureInitialized();

    // 1) 사용자 확보
    final user = await _waitForSignInEvent();

    // 2) 스코프 인가 확보
    var authorization =
    await user.authorizationClient.authorizationForScopes(_scopes);
    authorization ??=
    await user.authorizationClient.authorizeScopes(_scopes);

    // 3) AuthClient 생성
    _client = authorization.authClient(scopes: _scopes);
    _api = gcal.CalendarApi(_client!);
  }

  // ===== Read =====
  Future<List<gcal.Event>> listEvents({
    required String calendarId, // 보통 'primary'
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    await _ensureAuthClient();
    final resp = await _api!.events.list(
      calendarId,
      timeMin:
      (timeMin ?? DateTime.now().subtract(const Duration(days: 30))).toUtc(),
      timeMax:
      (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc(),
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
    String? colorId,
  }) async {
    await _ensureAuthClient();

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
    String? colorId,
  }) async {
    await _ensureAuthClient();

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
    await _ensureAuthClient();
    await _api!.events.delete(calendarId, eventId);
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect(); // 이전 세션 정리
    } catch (_) {}
    _client?.close();
    _client = null;
    _api = null;
  }
}
