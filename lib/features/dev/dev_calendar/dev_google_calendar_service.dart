import 'dart:async';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

import '../../../../utils/auth/google_auth_session.dart';

class DevGoogleCalendarService {
  auth.AuthClient? _client;
  gcal.CalendarApi? _api;

  Future<void> _ensureApi() async {
    if (_api != null) return;
    _client = await GoogleAuthSession.instance.safeClient();
    _api = gcal.CalendarApi(_client!);
  }

  Future<T> _withReauth<T>(Future<T> Function() op) async {
    try {
      await _ensureApi();
      return await op();
    } catch (e) {
      await GoogleAuthSession.instance.refreshIfNeeded();
      _api = null;
      await _ensureApi();
      return await op();
    }
  }

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

  Future<gcal.Event> createEvent({
    required String calendarId,
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
        final s = DateTime(start.year, start.month, start.day);

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

  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    return _withReauth(() async {
      final api = _api!;
      await api.events.delete(calendarId, eventId);
    });
  }

  Future<void> signOut() async {
    await GoogleAuthSession.instance.signOut();
    _client = null;
    _api = null;
  }
}
