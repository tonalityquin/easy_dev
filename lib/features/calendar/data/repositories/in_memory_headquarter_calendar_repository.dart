import 'dart:async';
import 'dart:math' as math;

import '../../application/headquarter_calendar_search_tokens.dart';
import '../../domain/models/headquarter_calendar_event.dart';
import '../../domain/models/headquarter_calendar_event_page.dart';
import '../../domain/models/headquarter_calendar_month_summary.dart';
import '../../domain/models/headquarter_calendar_search.dart';
import '../../domain/repositories/headquarter_calendar_repository.dart';

class InMemoryHeadquarterCalendarRepository
    implements HeadquarterCalendarRepository {
  final Map<String, HeadquarterCalendarEvent> _events =
      <String, HeadquarterCalendarEvent>{};
  final Map<String, Map<String, DateTime>> _acknowledgements =
      <String, Map<String, DateTime>>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _sequence = 0;

  @override
  Stream<HeadquarterCalendarMonthSummary> watchMonthSummary({
    required String monthKey,
  }) async* {
    yield _monthSummary(monthKey: monthKey);
    await for (final _ in _changes.stream) {
      yield _monthSummary(monthKey: monthKey);
    }
  }

  @override
  Stream<List<HeadquarterCalendarEvent>> watchFirstEventsForDate({
    required String dateKey,
    int limit = 20,
  }) async* {
    yield _eventsForDate(dateKey: dateKey, limit: limit);
    await for (final _ in _changes.stream) {
      yield _eventsForDate(dateKey: dateKey, limit: limit);
    }
  }

  @override
  Future<HeadquarterCalendarEventPage> fetchMoreEventsForDate({
    required String dateKey,
    required HeadquarterCalendarEventCursor cursor,
    int limit = 20,
  }) async {
    final safeLimit = limit <= 0 ? 20 : limit;
    final all = _filteredEventsForDate(dateKey: dateKey);
    final cursorIndex = all.indexWhere((event) => event.id == cursor.documentId);
    final start = cursorIndex < 0 ? all.length : cursorIndex + 1;
    final end = math.min(start + safeLimit, all.length);
    final page = start >= all.length
        ? const <HeadquarterCalendarEvent>[]
        : all.sublist(start, end);
    final last = page.isEmpty ? null : page.last;
    return HeadquarterCalendarEventPage(
      events: List<HeadquarterCalendarEvent>.unmodifiable(page),
      nextCursor: last == null ? null : _eventCursor(last),
      hasMore: end < all.length,
    );
  }

  @override
  Future<HeadquarterCalendarEvent?> readEvent(String eventId) async {
    return _events[eventId.trim()];
  }

  @override
  Future<String> createEvent({
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
  }) async {
    _validateDraft(draft);
    if (!draft.isRecurring) {
      final id = _nextId('event');
      _events[id] = _eventFromDraft(
        id: id,
        draft: draft,
        actor: actor,
      );
      _emit();
      return id;
    }
    final seriesId = _nextId('series');
    final occurrences = _eventsForRecurrence(
      seriesId: seriesId,
      draft: draft,
      actor: actor,
    );
    if (occurrences.isEmpty) {
      throw StateError('반복 일정 발생 건이 없습니다.');
    }
    for (final event in occurrences) {
      _events[event.id] = event;
    }
    _emit();
    return occurrences.first.id;
  }

  @override
  Future<void> updateEvent({
    required String eventId,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    bool applyToSeries = false,
  }) async {
    _validateDraft(draft);
    final current = _events[eventId.trim()];
    if (current == null || current.isDeleted) return;
    if (applyToSeries && current.isRecurring) {
      final affected = _events.values
          .where(
            (event) =>
                event.seriesId == current.seriesId &&
                !event.startDate.isBefore(current.startDate) &&
                !event.isDeleted,
          )
          .toList(growable: false);
      final now = DateTime.now();
      for (final event in affected) {
        _events[event.id] = event.copyWith(
          isDeleted: true,
          deletedAt: now,
          updatedAt: now,
          updatedBy: actor.userId,
          updatedByName: actor.userName,
        );
      }
      final replacements = _eventsForRecurrence(
        seriesId: current.seriesId,
        draft: draft,
        actor: actor,
        createdBy: current.createdBy,
        createdByName: current.createdByName,
        createdAt: current.createdAt,
      );
      for (final event in replacements) {
        _events[event.id] = event;
      }
      _emit();
      return;
    }
    _events[current.id] = _eventFromDraft(
      id: current.id,
      draft: draft,
      actor: actor,
      existing: current,
      seriesId: current.seriesId,
      occurrenceDateKey: current.occurrenceDateKey,
      recurrenceFrequency: current.recurrenceFrequency,
      recurrenceUntilDateKey: current.recurrenceUntilDateKey,
    );
    _emit();
  }

  @override
  Future<void> softDeleteEvent({
    required String eventId,
    required HeadquarterCalendarActor actor,
    bool applyToSeries = false,
  }) async {
    final current = _events[eventId.trim()];
    if (current == null || current.isDeleted) return;
    final now = DateTime.now();
    final targets = applyToSeries && current.isRecurring
        ? _events.values
            .where(
              (event) =>
                  event.seriesId == current.seriesId &&
                  !event.startDate.isBefore(current.startDate) &&
                  !event.isDeleted,
            )
            .toList(growable: false)
        : <HeadquarterCalendarEvent>[current];
    for (final event in targets) {
      _events[event.id] = event.copyWith(
        isDeleted: true,
        deletedAt: now,
        updatedAt: now,
        updatedBy: actor.userId,
        updatedByName: actor.userName,
      );
    }
    _emit();
  }

  @override
  Future<void> acknowledgeEvent({
    required HeadquarterCalendarEvent event,
    required HeadquarterCalendarActor actor,
  }) async {
    final eventId = event.id.trim();
    final userId = actor.userId.trim();
    if (eventId.isEmpty || userId.isEmpty) return;
    final values = _acknowledgements.putIfAbsent(
      eventId,
      () => <String, DateTime>{},
    );
    values[userId] = DateTime.now();
    _emit();
  }

  @override
  Future<Set<String>> readAcknowledgedEventIds({
    required List<String> eventIds,
    required String userId,
  }) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) return <String>{};
    return eventIds
        .where(
          (eventId) =>
              _acknowledgements[eventId]?.containsKey(cleanUserId) == true,
        )
        .toSet();
  }

  @override
  Future<HeadquarterCalendarSearchPage> searchEvents({
    required HeadquarterCalendarSearchQuery query,
    HeadquarterCalendarSearchCursor? cursor,
    int limit = 20,
  }) async {
    final normalized = normalizeHeadquarterCalendarSearchText(query.keyword);
    final terms = normalized
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) {
      return const HeadquarterCalendarSearchPage(
        events: <HeadquarterCalendarEvent>[],
        nextCursor: null,
        hasMore: false,
      );
    }
    final events = _events.values.where((event) {
      if (!query.includeDeleted && event.isDeleted) return false;
      if (query.eventType.isNotEmpty &&
          query.eventType != 'all' &&
          event.eventType != query.eventType) {
        return false;
      }
      if (query.priority.isNotEmpty &&
          query.priority != 'all' &&
          event.priority != query.priority) {
        return false;
      }
      if (query.fromDate != null &&
          event.endDate.isBefore(
            HeadquarterCalendarEvent.dateOnly(query.fromDate!),
          )) {
        return false;
      }
      if (query.toDate != null &&
          event.startDate.isAfter(
            HeadquarterCalendarEvent.dateOnly(query.toDate!),
          )) {
        return false;
      }
      final source = normalizeHeadquarterCalendarSearchText(
        '${event.title} ${event.description} ${event.createdByName} '
        '${event.eventType} ${event.priority}',
      );
      return terms.every(source.contains);
    }).toList()
      ..sort((left, right) {
        final date = right.startDateKey.compareTo(left.startDateKey);
        if (date != 0) return date;
        return right.id.compareTo(left.id);
      });
    final safeLimit = limit <= 0 ? 20 : limit;
    var start = 0;
    if (cursor != null) {
      final index = events.indexWhere((event) => event.id == cursor.documentId);
      start = index < 0 ? events.length : index + 1;
    }
    final end = math.min(start + safeLimit, events.length);
    final page = start >= events.length
        ? const <HeadquarterCalendarEvent>[]
        : events.sublist(start, end);
    final last = page.isEmpty ? null : page.last;
    return HeadquarterCalendarSearchPage(
      events: List<HeadquarterCalendarEvent>.unmodifiable(page),
      nextCursor: last == null
          ? null
          : HeadquarterCalendarSearchCursor(
              startDateKey: last.startDateKey,
              documentId: last.id,
            ),
      hasMore: end < events.length,
    );
  }

  void dispose() {
    _changes.close();
  }

  HeadquarterCalendarMonthSummary _monthSummary({
    required String monthKey,
  }) {
    final cleanMonth = monthKey.trim();
    if (cleanMonth.isEmpty) {
      return HeadquarterCalendarMonthSummary.empty(cleanMonth);
    }
    final days = <String, HeadquarterCalendarDaySummary>{};
    var eventCount = 0;
    var importantCount = 0;
    for (final event in _events.values) {
      if (event.isDeleted) continue;
      final dateKeys = event.dateKeys
          .where((dateKey) => dateKey.startsWith('$cleanMonth-'))
          .toList(growable: false);
      if (dateKeys.isEmpty) continue;
      eventCount += 1;
      if (event.isImportant) importantCount += 1;
      for (final dateKey in dateKeys) {
        final current = days[dateKey];
        days[dateKey] = HeadquarterCalendarDaySummary(
          dateKey: dateKey,
          count: (current?.count ?? 0) + 1,
          importantCount:
              (current?.importantCount ?? 0) + (event.isImportant ? 1 : 0),
        );
      }
    }
    return HeadquarterCalendarMonthSummary(
      monthKey: cleanMonth,
      days: Map<String, HeadquarterCalendarDaySummary>.unmodifiable(days),
      eventCount: eventCount,
      importantCount: importantCount,
    );
  }

  List<HeadquarterCalendarEvent> _eventsForDate({
    required String dateKey,
    required int limit,
  }) {
    final safeLimit = limit <= 0 ? 20 : limit;
    final values = _filteredEventsForDate(dateKey: dateKey);
    return List<HeadquarterCalendarEvent>.unmodifiable(
      values.take(safeLimit),
    );
  }

  List<HeadquarterCalendarEvent> _filteredEventsForDate({
    required String dateKey,
  }) {
    final cleanDate = dateKey.trim();
    if (cleanDate.isEmpty) return <HeadquarterCalendarEvent>[];
    final values = _events.values
        .where(
          (event) =>
              !event.isDeleted && event.dateKeys.contains(cleanDate),
        )
        .toList()
      ..sort(_compareDateListEvents);
    return values;
  }

  int _compareDateListEvents(
    HeadquarterCalendarEvent left,
    HeadquarterCalendarEvent right,
  ) {
    final priority = right.priorityRank.compareTo(left.priorityRank);
    if (priority != 0) return priority;
    final created = (right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(
      left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    if (created != 0) return created;
    return right.id.compareTo(left.id);
  }

  HeadquarterCalendarEvent _eventFromDraft({
    required String id,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    HeadquarterCalendarEvent? existing,
    String seriesId = '',
    String occurrenceDateKey = '',
    String? recurrenceFrequency,
    String? recurrenceUntilDateKey,
    DateTime? createdAt,
    String? createdBy,
    String? createdByName,
  }) {
    final start = HeadquarterCalendarEvent.dateOnly(draft.startDate);
    final rawEnd = HeadquarterCalendarEvent.dateOnly(draft.endDate);
    final end = rawEnd.isBefore(start) ? start : rawEnd;
    final dates = HeadquarterCalendarEvent.dateKeysBetween(start, end);
    final priority = draft.priority.trim().isEmpty
        ? 'normal'
        : draft.priority.trim();
    final now = DateTime.now();
    final eventType = draft.eventType.trim().isEmpty
        ? 'notice'
        : draft.eventType.trim();
    return HeadquarterCalendarEvent(
      id: id,
      title: draft.title.trim().isEmpty ? '제목 없음' : draft.title.trim(),
      description: draft.description.trim(),
      startDate: start,
      endDate: end,
      startDateKey: HeadquarterCalendarEvent.dateKeyOf(start),
      endDateKey: HeadquarterCalendarEvent.dateKeyOf(end),
      dateKeys: List<String>.unmodifiable(dates),
      monthKeys: List<String>.unmodifiable(
        HeadquarterCalendarEvent.monthKeysForDateKeys(dates),
      ),
      eventType: eventType,
      priority: priority,
      priorityRank: HeadquarterCalendarEvent.priorityRankOf(priority),
      createdBy: createdBy ?? existing?.createdBy ?? actor.userId,
      createdByName:
          createdByName ?? existing?.createdByName ?? actor.userName,
      updatedBy: actor.userId,
      updatedByName: actor.userName,
      createdAt: createdAt ?? existing?.createdAt ?? now,
      updatedAt: now,
      deletedAt: null,
      isDeleted: false,
      requiresAck: draft.requiresAck,
      seriesId: seriesId,
      occurrenceDateKey: occurrenceDateKey,
      recurrenceFrequency: recurrenceFrequency ??
          (draft.isRecurring ? draft.recurrenceFrequency : 'none'),
      recurrenceInterval: draft.recurrenceInterval.clamp(1, 4).toInt(),
      recurrenceUntilDateKey: recurrenceUntilDateKey ??
          (draft.isRecurring
              ? HeadquarterCalendarEvent.dateKeyOf(
                  draft.recurrenceUntilDate,
                )
              : ''),
      searchTokens: List<String>.unmodifiable(
        buildHeadquarterCalendarSearchTokens(
          title: draft.title,
          description: draft.description,
          eventType: eventType,
          priority: priority,
          createdByName:
              createdByName ?? existing?.createdByName ?? actor.userName,
        ),
      ),
      searchTokenVersion: headquarterCalendarSearchTokenVersion,
      schemaVersion: 3,
    );
  }

  List<HeadquarterCalendarEvent> _eventsForRecurrence({
    required String seriesId,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
  }) {
    final starts = _recurrenceStarts(draft);
    final duration = HeadquarterCalendarEvent.dateOnly(draft.endDate)
        .difference(HeadquarterCalendarEvent.dateOnly(draft.startDate))
        .inDays;
    return starts.map((start) {
      final occurrenceDraft = HeadquarterCalendarEventDraft(
        title: draft.title,
        description: draft.description,
        startDate: start,
        endDate: start.add(Duration(days: duration)),
        eventType: draft.eventType,
        priority: draft.priority,
        requiresAck: draft.requiresAck,
        recurrenceFrequency: draft.recurrenceFrequency,
        recurrenceInterval: draft.recurrenceInterval,
        recurrenceUntilDate: draft.recurrenceUntilDate,
      );
      final occurrenceDateKey = HeadquarterCalendarEvent.dateKeyOf(start);
      return _eventFromDraft(
        id: _nextId('event'),
        draft: occurrenceDraft,
        actor: actor,
        seriesId: seriesId,
        occurrenceDateKey: occurrenceDateKey,
        recurrenceFrequency: draft.recurrenceFrequency,
        recurrenceUntilDateKey: HeadquarterCalendarEvent.dateKeyOf(
          draft.recurrenceUntilDate,
        ),
        createdAt: createdAt,
        createdBy: createdBy,
        createdByName: createdByName,
      );
    }).toList(growable: false);
  }

  List<DateTime> _recurrenceStarts(HeadquarterCalendarEventDraft draft) {
    final start = HeadquarterCalendarEvent.dateOnly(draft.startDate);
    var until = HeadquarterCalendarEvent.dateOnly(draft.recurrenceUntilDate);
    if (until.isBefore(start)) until = start;
    final maxUntil = start.add(const Duration(days: 365));
    if (until.isAfter(maxUntil)) until = maxUntil;
    final interval = draft.recurrenceInterval.clamp(1, 4).toInt();
    final values = <DateTime>[];
    var current = start;
    while (!current.isAfter(until) && values.length < 366) {
      values.add(current);
      if (draft.recurrenceFrequency == 'monthly') {
        current = _addMonths(current, interval);
      } else {
        current = current.add(Duration(days: 7 * interval));
      }
    }
    return values;
  }

  DateTime _addMonths(DateTime date, int months) {
    final first = DateTime(date.year, date.month + months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, math.min(date.day, lastDay));
  }

  void _validateDraft(HeadquarterCalendarEventDraft draft) {
    if (draft.title.trim().isEmpty) {
      throw ArgumentError('일정 제목이 필요합니다.');
    }
    final start = HeadquarterCalendarEvent.dateOnly(draft.startDate);
    final end = HeadquarterCalendarEvent.dateOnly(draft.endDate);
    if (end.isBefore(start)) {
      throw ArgumentError('종료일은 시작일보다 빠를 수 없습니다.');
    }
    if (end.difference(start).inDays > 365) {
      throw ArgumentError('일정 기간은 최대 366일입니다.');
    }
    if (draft.isRecurring &&
        !const <String>{'weekly', 'monthly'}
            .contains(draft.recurrenceFrequency)) {
      throw ArgumentError('지원하지 않는 반복 유형입니다.');
    }
  }

  HeadquarterCalendarEventCursor _eventCursor(
    HeadquarterCalendarEvent event,
  ) {
    return HeadquarterCalendarEventCursor(
      priorityRank: event.priorityRank,
      createdAtMillis:
          (event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .millisecondsSinceEpoch,
      documentId: event.id,
    );
  }

  String _nextId(String prefix) {
    _sequence += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_sequence';
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }
}
