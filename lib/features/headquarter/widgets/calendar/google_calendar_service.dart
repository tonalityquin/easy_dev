import 'package:googleapis/calendar/v3.dart' as gcal;
import '../../../../app/auth/google_auth_session.dart';
import '../../../dev/debug/debug_api_logger.dart';

class GoogleCalendarAccessEntry {
  const GoogleCalendarAccessEntry({
    required this.id,
    required this.summary,
    required this.accessRole,
    required this.primary,
    required this.selected,
    required this.hidden,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.timeZone,
  });

  final String id;
  final String summary;
  final String accessRole;
  final bool primary;
  final bool selected;
  final bool hidden;
  final String? backgroundColor;
  final String? foregroundColor;
  final String? timeZone;

  String get normalizedAccessRole => accessRole.trim().toLowerCase();

  bool get canEditEvents =>
      normalizedAccessRole == 'owner' || normalizedAccessRole == 'writer';

  bool get canManageSharing => normalizedAccessRole == 'owner';

  String get displayName {
    final normalizedSummary = summary.trim();
    return normalizedSummary.isEmpty ? id : normalizedSummary;
  }

  String get accessLabel {
    switch (normalizedAccessRole) {
      case 'owner':
        return '변경 및 공유 관리';
      case 'writer':
        return '일정 변경';
      case 'reader':
        return '일정 보기';
      case 'freebusyreader':
        return '한가함/바쁨 보기';
      default:
        return '권한 확인 필요';
    }
  }
}


class GoogleCalendarEventSyncResult {
  const GoogleCalendarEventSyncResult({
    required this.events,
    required this.nextSyncToken,
    required this.pageCount,
    required this.incremental,
  });

  final List<gcal.Event> events;
  final String? nextSyncToken;
  final int pageCount;
  final bool incremental;
}

class GoogleCalendarSyncTokenExpiredException implements Exception {
  const GoogleCalendarSyncTokenExpiredException();

  @override
  String toString() => 'google_calendar_sync_token_expired';
}

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


  Future<List<GoogleCalendarAccessEntry>> listAccessibleCalendars({
    required String accountEmail,
  }) async {
    try {
      return await _runWithAuthRetry<List<GoogleCalendarAccessEntry>>(
        accountEmail: accountEmail,
        operation: 'listAccessibleCalendars',
        request: (api) async {
          final result = <GoogleCalendarAccessEntry>[];
          String? pageToken;
          do {
            final response = await api.calendarList.list(
              maxResults: 250,
              pageToken: pageToken,
              showHidden: true,
            );
            for (final entry
                in response.items ?? const <gcal.CalendarListEntry>[]) {
              if (entry.deleted == true) continue;
              final id = entry.id?.trim() ?? '';
              if (id.isEmpty) continue;
              result.add(
                GoogleCalendarAccessEntry(
                  id: id,
                  summary: (entry.summaryOverride?.trim().isNotEmpty == true
                          ? entry.summaryOverride
                          : entry.summary)
                      ?.trim() ??
                      '',
                  accessRole: entry.accessRole?.trim().toLowerCase() ??
                      'unknown',
                  primary: entry.primary == true,
                  selected: entry.selected == true,
                  hidden: entry.hidden == true,
                  backgroundColor: entry.backgroundColor?.trim(),
                  foregroundColor: entry.foregroundColor?.trim(),
                  timeZone: entry.timeZone?.trim(),
                ),
              );
            }
            final next = response.nextPageToken?.trim();
            pageToken = next?.isNotEmpty == true ? next : null;
          } while (pageToken != null);
          result.sort((a, b) {
            if (a.primary != b.primary) return a.primary ? -1 : 1;
            if (a.canEditEvents != b.canEditEvents) {
              return a.canEditEvents ? -1 : 1;
            }
            return a.displayName.toLowerCase().compareTo(
                  b.displayName.toLowerCase(),
                );
          });
          return result;
        },
      );
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.listAccessibleCalendars',
        message: '접근 가능한 Google Calendar 목록 조회 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail.trim().toLowerCase(),
        },
        tags: const <String>[_tCal, _tCalService, _tCalList],
      );
      rethrow;
    }
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

  Future<String> calendarAccessRole({
    required String accountEmail,
    required String calendarId,
  }) async {
    try {
      final accessRole = await _runWithAuthRetry<String?>(
        accountEmail: accountEmail,
        operation: 'calendarAccessRole',
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
      return accessRole?.isNotEmpty == true ? accessRole! : 'unknown';
    } catch (e) {
      await _logApiError(
        tag: 'GoogleCalendarService.calendarAccessRole',
        message: 'Calendar 권한 조회 실패',
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

  Future<String> verifyCalendarWriteAccess({
    required String accountEmail,
    required String calendarId,
  }) async {
    try {
      final accessRole = await calendarAccessRole(
        accountEmail: accountEmail,
        calendarId: calendarId,
      );
      if (accessRole != 'owner' && accessRole != 'writer') {
        throw StateError('calendar_write_access_required');
      }
      return accessRole;
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
    final result = await listEventsSnapshot(
      accountEmail: accountEmail,
      calendarId: calendarId,
      timeMin: timeMin,
      timeMax: timeMax,
      maxResults: maxResults,
    );
    return result.events;
  }

  Future<GoogleCalendarEventSyncResult> listEventsSnapshot({
    String? accountEmail,
    required String calendarId,
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 500,
  }) async {
    final tMin =
        (timeMin ?? DateTime.now().subtract(const Duration(days: 30))).toUtc();
    final tMax =
        (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc();
    return _listEventPages(
      accountEmail: accountEmail,
      calendarId: calendarId,
      timeMin: tMin,
      timeMax: tMax,
      maxResults: maxResults,
    );
  }

  Future<GoogleCalendarEventSyncResult> listEventChanges({
    String? accountEmail,
    required String calendarId,
    required String syncToken,
    int maxResults = 500,
  }) async {
    final normalizedToken = syncToken.trim();
    if (normalizedToken.isEmpty) {
      throw ArgumentError.value(syncToken, 'syncToken');
    }
    return _listEventPages(
      accountEmail: accountEmail,
      calendarId: calendarId,
      syncToken: normalizedToken,
      maxResults: maxResults,
    );
  }

  Future<GoogleCalendarEventSyncResult> _listEventPages({
    String? accountEmail,
    required String calendarId,
    DateTime? timeMin,
    DateTime? timeMax,
    String? syncToken,
    required int maxResults,
  }) async {
    final incremental = syncToken?.isNotEmpty == true;
    try {
      return await _runWithAuthRetry<GoogleCalendarEventSyncResult>(
        accountEmail: accountEmail,
        operation: incremental ? 'listEventChanges' : 'listEventsSnapshot',
        request: (api) async {
          final events = <gcal.Event>[];
          String? pageToken;
          String? nextSyncToken;
          var pageCount = 0;
          do {
            gcal.Events response;
            try {
              response = await api.events.list(
                calendarId,
                timeMin: incremental ? null : timeMin,
                timeMax: incremental ? null : timeMax,
                singleEvents: true,
                orderBy: incremental ? null : 'startTime',
                maxResults: maxResults,
                pageToken: pageToken,
                syncToken: incremental ? syncToken : null,
              );
            } on gcal.DetailedApiRequestError catch (error) {
              if (incremental && error.status == 410) {
                throw const GoogleCalendarSyncTokenExpiredException();
              }
              rethrow;
            }
            pageCount += 1;
            events.addAll(response.items ?? const <gcal.Event>[]);
            pageToken = response.nextPageToken?.trim();
            if (pageToken?.isEmpty == true) pageToken = null;
            final candidateToken = response.nextSyncToken?.trim();
            if (candidateToken?.isNotEmpty == true) {
              nextSyncToken = candidateToken;
            }
          } while (pageToken != null);
          return GoogleCalendarEventSyncResult(
            events: events,
            nextSyncToken: nextSyncToken,
            pageCount: pageCount,
            incremental: incremental,
          );
        },
      );
    } catch (e) {
      await _logApiError(
        tag: incremental
            ? 'GoogleCalendarService.listEventChanges'
            : 'GoogleCalendarService.listEventsSnapshot',
        message: incremental
            ? 'Calendar 증분 events.list 실패'
            : 'Calendar 전체 events.list 실패',
        error: e,
        extra: <String, dynamic>{
          'accountEmail': accountEmail?.trim().toLowerCase(),
          'calendarId': calendarId,
          'incremental': incremental,
          'timeMinUtc': timeMin?.toIso8601String(),
          'timeMaxUtc': timeMax?.toIso8601String(),
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
    String? expectedEtag,
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
        request: (api) async {
          final normalizedEtag = expectedEtag?.trim();
          if (normalizedEtag?.isNotEmpty == true) {
            final current = await api.events.get(calendarId, eventId);
            if (current.etag?.trim() != normalizedEtag) {
              throw StateError('calendar_event_conflict');
            }
          }
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
          'expectedEtag': expectedEtag,
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
    String? expectedEtag,
  }) async {
    try {
      await _runWithAuthRetry<void>(
        accountEmail: accountEmail,
        operation: 'deleteEvent',
        request: (api) async {
          final normalizedEtag = expectedEtag?.trim();
          if (normalizedEtag?.isNotEmpty == true) {
            final current = await api.events.get(calendarId, eventId);
            if (current.etag?.trim() != normalizedEtag) {
              throw StateError('calendar_event_conflict');
            }
          }
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
          'expectedEtag': expectedEtag,
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
