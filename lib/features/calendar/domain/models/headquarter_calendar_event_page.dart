import 'headquarter_calendar_event.dart';

class HeadquarterCalendarEventCursor {
  const HeadquarterCalendarEventCursor({
    required this.priorityRank,
    required this.createdAtMillis,
    required this.documentId,
  });

  final int priorityRank;
  final int createdAtMillis;
  final String documentId;
}

class HeadquarterCalendarEventPage {
  const HeadquarterCalendarEventPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<HeadquarterCalendarEvent> events;
  final HeadquarterCalendarEventCursor? nextCursor;
  final bool hasMore;
}
