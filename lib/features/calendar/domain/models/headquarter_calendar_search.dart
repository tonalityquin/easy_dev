import 'headquarter_calendar_event.dart';

class HeadquarterCalendarSearchQuery {
  const HeadquarterCalendarSearchQuery({
    required this.keyword,
    required this.userId,
    required this.scopeFilter,
    required this.eventType,
    required this.priority,
    required this.fromDate,
    required this.toDate,
    required this.includeDeleted,
  });

  final String keyword;
  final String userId;
  final String scopeFilter;
  final String eventType;
  final String priority;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool includeDeleted;
}

class HeadquarterCalendarSearchCursor {
  const HeadquarterCalendarSearchCursor({
    required this.startDateKey,
    required this.documentId,
  });

  final String startDateKey;
  final String documentId;
}

class HeadquarterCalendarSearchPage {
  const HeadquarterCalendarSearchPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<HeadquarterCalendarEvent> events;
  final HeadquarterCalendarSearchCursor? nextCursor;
  final bool hasMore;
}

class HeadquarterCalendarMigrationBatch {
  const HeadquarterCalendarMigrationBatch({
    required this.scannedCount,
    required this.updatedCount,
    required this.hasMore,
    required this.completed,
  });

  final int scannedCount;
  final int updatedCount;
  final bool hasMore;
  final bool completed;
}
