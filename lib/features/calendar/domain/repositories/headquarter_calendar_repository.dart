import '../models/headquarter_calendar_attendance.dart';
import '../models/headquarter_calendar_event.dart';
import '../models/headquarter_calendar_event_page.dart';
import '../models/headquarter_calendar_month_summary.dart';
import '../models/headquarter_calendar_search.dart';

abstract class HeadquarterCalendarRepository {
  Stream<HeadquarterCalendarMonthSummary> watchMonthSummary({
    required String monthKey,
    required String userId,
    String scopeFilter = 'all',
  });

  Stream<List<HeadquarterCalendarEvent>> watchFirstEventsForDate({
    required String dateKey,
    required String userId,
    String scopeFilter = 'all',
    int limit = 20,
  });

  Future<HeadquarterCalendarEventPage> fetchMoreEventsForDate({
    required String dateKey,
    required String userId,
    String scopeFilter = 'all',
    required HeadquarterCalendarEventCursor cursor,
    int limit = 20,
  });

  Future<HeadquarterCalendarEvent?> readEvent(String eventId);

  Future<String> createEvent({
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
  });

  Future<void> updateEvent({
    required String eventId,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    bool applyToSeries = false,
  });

  Future<void> softDeleteEvent({
    required String eventId,
    required HeadquarterCalendarActor actor,
    bool applyToSeries = false,
  });

  Future<void> acknowledgeEvent({
    required HeadquarterCalendarEvent event,
    required HeadquarterCalendarActor actor,
  });

  Future<Set<String>> readAcknowledgedEventIds({
    required List<String> eventIds,
    required String userId,
  });

  Future<HeadquarterCalendarSearchPage> searchEvents({
    required HeadquarterCalendarSearchQuery query,
    HeadquarterCalendarSearchCursor? cursor,
    int limit = 20,
  });

  Future<HeadquarterCalendarMigrationBatch> migrateLegacyEvents({
    int limit = 50,
  });

  Future<bool> isLegacyMigrationComplete();

  Future<List<HeadquarterCalendarStaffMember>> readStaffMembers({
    bool forceRefresh = false,
  });

  Future<void> setAttendanceStatus({
    required HeadquarterCalendarEvent event,
    required HeadquarterCalendarActor actor,
    required String status,
  });

  Future<List<HeadquarterCalendarReceipt>> readReceipts({
    required String eventId,
  });

  Future<List<HeadquarterCalendarAttendanceResponse>> readAttendanceResponses({
    required String eventId,
  });
}
