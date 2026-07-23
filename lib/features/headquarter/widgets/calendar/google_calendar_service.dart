import 'package:googleapis/calendar/v3.dart' as gcal;
import '../../../../app/auth/google_auth_session.dart';
import '../../../dev/debug/debug_api_logger.dart';

class GoogleCalendarService {
  static const int _allDayReminderMinutes = 7 * 60;
  static const String _tCal = 'calendar';
  static const String _tCalService = 'calendar/service';
  static const String _tCalAuth = 'calendar/auth';
  static const String _tCalList = 'calendar/list';
  static const String _tCalCreate = 'calendar/create';
  static const String _tCalUpdate = 'calendar/update';
  static const String _tCalDelete = 'calendar/delete';
  static const String _tCalVerify = 'calendar/verify';
  static const String _tCalVerifyWrite = 'calendar/verify-write';
  static const String _tCalRetry = 'calendar/retry';

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
    } catch (_) {}
  }

  String? _normalizeAccountEmail(String? accountEmail) {
    final normalized = accountEmail?.trim().toLowerCase();
    return normalized?.isNotEmpty == true ? normalized : null;
  }

  Future<gcal.CalendarApi> _createApi({String? accountEmail}) async {
    final normalizedEmail = _normalizeAccountEmail(accountEmail);

    try {
      final client = normalizedEmail == null
          ? await GoogleAuthSession.instance.safeClient()
          : await GoogleAuthSession.instance.safeClientFor(
              expectedEmail: normalizedEmail,
            );
      return gcal.CalendarApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService._createApi',
        message: 'Google 인증 클라이언트 또는 CalendarApi 초기화 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': normalizedEmail,
        },
        tags: const <String>[_tCal, _tCalService, _tCalAuth],
      );
      rethrow;
    }
  }

  Future<T> _runWithAuthRetry<T>({
    String? accountEmail,
    required String operation,
    required Future<T> Function(gcal.CalendarApi api) request,
  }) async {
    final normalizedEmail = _normalizeAccountEmail(accountEmail);

    try {
      final api = await _createApi(accountEmail: normalizedEmail);
      return await request(api);
    } catch (e, st) {
      if (!GoogleAuthSession.isInvalidTokenError(e)) {
        Error.throwWithStackTrace(e, st);
      }

      await _logApiError(
        tag: 'GoogleCalendarService._runWithAuthRetry',
        message: 'Google Calendar 인증 오류 감지 후 자동 갱신 시작',
        error: e,
        extra: <String, dynamic>{
          'operation': operation,
          'accountEmail': normalizedEmail,
        },
        tags: const <String>[
          _tCal,
          _tCalService,
          _tCalAuth,
          _tCalRetry,
        ],
      );

      try {
        GoogleAuthSession.instance.invalidateClient(
          accountEmail: normalizedEmail,
        );
        await GoogleAuthSession.instance.refreshClient(
          expectedEmail: normalizedEmail,
        );
      } catch (refreshError, refreshStack) {
        await _logApiError(
          tag: 'GoogleCalendarService._runWithAuthRetry',
          message: 'Google Calendar 인증 자동 갱신 실패',
          error: refreshError,
          extra: <String, dynamic>{
            'operation': operation,
            'accountEmail': normalizedEmail,
          },
          tags: const <String>[
            _tCal,
            _tCalService,
            _tCalAuth,
            _tCalRetry,
          ],
        );
        Error.throwWithStackTrace(refreshError, refreshStack);
      }

      try {
        final refreshedApi = await _createApi(accountEmail: normalizedEmail);
        return await request(refreshedApi);
      } catch (retryError, retryStack) {
        await _logApiError(
          tag: 'GoogleCalendarService._runWithAuthRetry',
          message: 'Google Calendar 인증 갱신 후 1회 재시도 실패',
          error: retryError,
          extra: <String, dynamic>{
            'operation': operation,
            'accountEmail': normalizedEmail,
          },
          tags: const <String>[
            _tCal,
            _tCalService,
            _tCalAuth,
            _tCalRetry,
          ],
        );
        Error.throwWithStackTrace(retryError, retryStack);
      }
    }
  }

  void resetAuthenticatedClient({String? accountEmail}) {
    GoogleAuthSession.instance.invalidateClient(accountEmail: accountEmail);
  }

  Future<void> verifyCalendarAccess({
    required String accountEmail,
    required String calendarId,
  }) async {
    final now = DateTime.now().toUtc();

    try {
      await _runWithAuthRetry<void>(
        accountEmail: accountEmail,
        operation: 'verifyCalendarAccess',
        request: (api) async {
          await api.events.list(
            calendarId,
            timeMin: now.subtract(const Duration(days: 1)),
            timeMax: now.add(const Duration(days: 1)),
            singleEvents: true,
            orderBy: 'startTime',
            maxResults: 1,
          );
        },
      );
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.verifyCalendarAccess',
        message: 'Calendar 접근 확인 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail.trim().toLowerCase(),
          'calendarId': calendarId,
        },
        tags: const <String>[_tCal, _tCalService, _tCalVerify],
      );
      rethrow;
    }
  }

  Future<void> verifyCalendarWriteAccess({
    required String accountEmail,
    required String calendarId,
  }) async {
    try {
      final accessRole = await _runWithAuthRetry<String?>(
        accountEmail: accountEmail,
        operation: 'verifyCalendarWriteAccess',
        request: (api) async {
          gcal.CalendarListEntry? entry;
          if (calendarId.trim().toLowerCase() == 'primary') {
            final response = await api.calendarList.list(
              maxResults: 250,
              showHidden: true,
            );
            for (final candidate
                in response.items ?? const <gcal.CalendarListEntry>[]) {
              if (candidate.primary == true) {
                entry = candidate;
                break;
              }
            }
          } else {
            entry = await api.calendarList.get(calendarId);
          }
          return entry?.accessRole?.trim().toLowerCase();
        },
      );
      if (accessRole != 'owner' && accessRole != 'writer') {
        throw StateError('calendar_write_access_required');
      }
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.verifyCalendarWriteAccess',
        message: 'Calendar 쓰기 권한 확인 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail.trim().toLowerCase(),
          'calendarId': calendarId,
        },
        tags: const <String>[_tCal, _tCalService, _tCalVerifyWrite],
      );
      rethrow;
    }
  }

  Future<List<gcal.Event>> listEvents({
    String? accountEmail,
    required String calendarId,
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    final tMin =
        (timeMin ?? DateTime.now().subtract(const Duration(days: 30))).toUtc();
    final tMax =
        (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc();

    try {
      return await _runWithAuthRetry<List<gcal.Event>>(
        accountEmail: accountEmail,
        operation: 'listEvents',
        request: (api) async {
          final resp = await api.events.list(
            calendarId,
            timeMin: tMin,
            timeMax: tMax,
            singleEvents: true,
            orderBy: 'startTime',
            maxResults: maxResults,
          );
          return resp.items ?? <gcal.Event>[];
        },
      );
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.listEvents',
        message: 'Calendar events.list 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail?.trim().toLowerCase(),
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

  Future<gcal.Event> createEvent({
    String? accountEmail,
    required String calendarId,
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? colorId,
    String? eventId,
    Map<String, String>? privateProperties,
  }) async {
    final normalizedEventId = eventId?.trim();

    gcal.Event buildEvent() {
      final event = gcal.Event()
        ..summary = summary
        ..description = description;

      if (normalizedEventId?.isNotEmpty == true) {
        event.id = normalizedEventId;
      }
      if (colorId != null && colorId.isNotEmpty) {
        event.colorId = colorId;
      }
      if (privateProperties != null) {
        event.extendedProperties = gcal.EventExtendedProperties(
          private: Map<String, String>.from(privateProperties),
        );
      }

      if (allDay) {
        final s = DateTime(start.year, start.month, start.day);
        final e = DateTime(end.year, end.month, end.day);
        event.start = gcal.EventDateTime(date: s);
        event.end = gcal.EventDateTime(date: e);
        event.reminders = _allDayReminders();
      } else {
        event.start = gcal.EventDateTime(dateTime: start.toUtc());
        event.end = gcal.EventDateTime(dateTime: end.toUtc());
      }

      return event;
    }

    try {
      return await _runWithAuthRetry<gcal.Event>(
        accountEmail: accountEmail,
        operation: 'createEvent',
        request: (api) {
          return api.events.insert(buildEvent(), calendarId);
        },
      );
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.createEvent',
        message: 'Calendar events.insert 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail?.trim().toLowerCase(),
          'calendarId': calendarId,
          'eventId': normalizedEventId,
          'summaryLen': summary.trim().length,
          'hasDescription': (description ?? '').trim().isNotEmpty,
          'allDay': allDay,
          'start': allDay
              ? DateTime(start.year, start.month, start.day).toIso8601String()
              : start.toUtc().toIso8601String(),
          'end': allDay
              ? DateTime(end.year, end.month, end.day).toIso8601String()
              : end.toUtc().toIso8601String(),
          'colorId': colorId,
          'privatePropertyCount': privateProperties?.length ?? 0,
        },
        tags: const <String>[_tCal, _tCalService, _tCalCreate],
      );
      rethrow;
    }
  }

  Future<gcal.Event> updateEvent({
    String? accountEmail,
    required String calendarId,
    required String eventId,
    String? summary,
    String? description,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? colorId,
    Map<String, String>? privateProperties,
  }) async {
    gcal.Event buildPatch() {
      final patch = gcal.Event();
      if (summary != null) patch.summary = summary;
      if (description != null) patch.description = description;
      if (colorId != null) patch.colorId = colorId;
      if (privateProperties != null) {
        patch.extendedProperties = gcal.EventExtendedProperties(
          private: Map<String, String>.from(privateProperties),
        );
      }

      if (start != null && end != null) {
        if (allDay == true) {
          final s = DateTime(start.year, start.month, start.day);
          final e = DateTime(end.year, end.month, end.day);
          patch.start = gcal.EventDateTime(date: s);
          patch.end = gcal.EventDateTime(date: e);
          patch.reminders = _allDayReminders();
        } else {
          patch.start = gcal.EventDateTime(dateTime: start.toUtc());
          patch.end = gcal.EventDateTime(dateTime: end.toUtc());
        }
      } else if (allDay == true) {
        patch.reminders = _allDayReminders();
      }

      return patch;
    }

    try {
      return await _runWithAuthRetry<gcal.Event>(
        accountEmail: accountEmail,
        operation: 'updateEvent',
        request: (api) {
          return api.events.patch(buildPatch(), calendarId, eventId);
        },
      );
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.updateEvent',
        message: 'Calendar events.patch 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail?.trim().toLowerCase(),
          'calendarId': calendarId,
          'eventId': eventId,
          'hasSummary': summary != null,
          'hasDescription': description != null,
          'hasTimeRange': start != null && end != null,
          'allDay': allDay,
          'colorIdProvided': colorId != null,
          'privatePropertyCount': privateProperties?.length ?? 0,
        },
        tags: const <String>[_tCal, _tCalService, _tCalUpdate],
      );
      rethrow;
    }
  }

  static gcal.EventReminders _allDayReminders() {
    return gcal.EventReminders()
      ..useDefault = false
      ..overrides = <gcal.EventReminder>[
        gcal.EventReminder()
          ..method = 'popup'
          ..minutes = _allDayReminderMinutes,
      ];
  }

  Future<void> deleteEvent({
    String? accountEmail,
    required String calendarId,
    required String eventId,
  }) async {
    try {
      await _runWithAuthRetry<void>(
        accountEmail: accountEmail,
        operation: 'deleteEvent',
        request: (api) async {
          await api.events.delete(calendarId, eventId);
        },
      );
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.deleteEvent',
        message: 'Calendar events.delete 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail?.trim().toLowerCase(),
          'calendarId': calendarId,
          'eventId': eventId,
        },
        tags: const <String>[_tCal, _tCalService, _tCalDelete],
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleAuthSession.instance.signOut();
      resetAuthenticatedClient();
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
