import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/headquarter_calendar_audience.dart';
import '../../application/headquarter_calendar_search_tokens.dart';
import '../../domain/models/headquarter_calendar_attendance.dart';
import '../../domain/models/headquarter_calendar_event.dart';
import '../../domain/models/headquarter_calendar_event_page.dart';
import '../../domain/models/headquarter_calendar_month_summary.dart';
import '../../domain/models/headquarter_calendar_search.dart';
import '../../domain/repositories/headquarter_calendar_repository.dart';

class FirestoreHeadquarterCalendarRepository
    implements HeadquarterCalendarRepository {
  FirestoreHeadquarterCalendarRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  List<HeadquarterCalendarStaffMember>? _staffCache;
  DateTime? _staffCacheAt;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('headquarter_calendar_events');
  CollectionReference<Map<String, dynamic>> get _months =>
      _firestore.collection('headquarter_calendar_months');
  CollectionReference<Map<String, dynamic>> get _userMonths =>
      _firestore.collection('headquarter_calendar_user_months');
  CollectionReference<Map<String, dynamic>> get _series =>
      _firestore.collection('headquarter_calendar_series');
  CollectionReference<Map<String, dynamic>> get _receipts =>
      _firestore.collection('headquarter_calendar_event_receipts');
  CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection('headquarter_calendar_event_attendance');
  CollectionReference<Map<String, dynamic>> get _logs =>
      _firestore.collection('headquarter_calendar_event_logs');
  DocumentReference<Map<String, dynamic>> get _migrationMeta =>
      _firestore.collection('headquarter_calendar_meta').doc('schema_v2');

  @override
  Stream<HeadquarterCalendarMonthSummary> watchMonthSummary({
    required String monthKey,
    required String userId,
    String scopeFilter = 'all',
  }) {
    final cleanMonth = monthKey.trim();
    final cleanUser = userId.trim();
    if (cleanMonth.isEmpty) {
      return Stream<HeadquarterCalendarMonthSummary>.value(
        HeadquarterCalendarMonthSummary.empty(cleanMonth),
      );
    }
    final company = _months.doc(cleanMonth).snapshots().map(
          (snapshot) => HeadquarterCalendarMonthSummary.fromMap(
            monthKey: cleanMonth,
            data: snapshot.data(),
          ),
        );
    if (scopeFilter == 'company' || cleanUser.isEmpty) return company;
    final personal = _userMonths
        .doc(_userMonthDocId(cleanUser, cleanMonth))
        .snapshots()
        .map(
          (snapshot) => HeadquarterCalendarMonthSummary.fromMap(
            monthKey: cleanMonth,
            data: snapshot.data(),
          ),
        );
    if (scopeFilter == 'personal') return personal;
    return _combineSummaryStreams(company, personal);
  }

  @override
  Stream<List<HeadquarterCalendarEvent>> watchFirstEventsForDate({
    required String dateKey,
    required String userId,
    String scopeFilter = 'all',
    int limit = 20,
  }) {
    final cleanDate = dateKey.trim();
    if (cleanDate.isEmpty) {
      return Stream<List<HeadquarterCalendarEvent>>.value(
        const <HeadquarterCalendarEvent>[],
      );
    }
    final safeLimit = limit <= 0 ? 20 : limit;
    return _modernDateQuery(cleanDate, userId, scopeFilter)
        .limit(safeLimit)
        .snapshots()
        .map(_eventsFromSnapshot);
  }

  @override
  Future<HeadquarterCalendarEventPage> fetchMoreEventsForDate({
    required String dateKey,
    required String userId,
    String scopeFilter = 'all',
    required HeadquarterCalendarEventCursor cursor,
    int limit = 20,
  }) async {
    final safeLimit = limit <= 0 ? 20 : limit;
    final snapshot = await _modernDateQuery(dateKey.trim(), userId, scopeFilter)
        .startAfter(<Object>[
          cursor.priorityRank,
          Timestamp.fromMillisecondsSinceEpoch(cursor.createdAtMillis),
          cursor.documentId,
        ])
        .limit(safeLimit + 1)
        .get();
    return _eventPage(snapshot.docs, safeLimit);
  }

  @override
  Future<HeadquarterCalendarEvent?> readEvent(String eventId) async {
    final id = eventId.trim();
    if (id.isEmpty) return null;
    final snapshot = await _events.doc(id).get();
    final data = snapshot.data();
    if (data == null) return null;
    return HeadquarterCalendarEvent.fromMap(snapshot.id, data);
  }

  @override
  Future<String> createEvent({
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
  }) async {
    _validateDraft(draft);
    if (!draft.isRecurring) {
      final eventDoc = _events.doc();
      final event = _eventFromDraft(
        id: eventDoc.id,
        draft: draft,
        actor: actor,
        existing: null,
      );
      await _firestore.runTransaction((transaction) async {
        await _applySummaryAdjustments(
          transaction,
          _summaryAdjustmentsForEvents(<HeadquarterCalendarEvent>[event], 1),
        );
        transaction.set(eventDoc, event.toCreateMap());
        transaction.set(
          _logs.doc(),
          _logData(
            eventId: event.id,
            action: 'create',
            actor: actor,
            changedFields: const <String>[
              'title',
              'startDateKey',
              'endDateKey',
              'scopeKey',
              'priority',
              'requiresAck',
              'attendeeMode',
            ],
          ),
        );
      });
      return event.id;
    }

    final seriesDoc = _series.doc();
    final events = _eventsForRecurrence(
      seriesId: seriesDoc.id,
      draft: draft,
      actor: actor,
      existingCreatedBy: null,
      existingCreatedByName: null,
    );
    if (events.isEmpty) throw StateError('반복 일정 발생 건이 없습니다.');
    await _firestore.runTransaction((transaction) async {
      await _applySummaryAdjustments(
        transaction,
        _summaryAdjustmentsForEvents(events, 1),
      );
      for (final event in events) {
        transaction.set(_events.doc(event.id), event.toCreateMap());
      }
      transaction.set(seriesDoc, _seriesData(seriesDoc.id, draft, actor));
      transaction.set(
        _logs.doc(),
        _logData(
          eventId: seriesDoc.id,
          action: 'createSeries',
          actor: actor,
          changedFields: const <String>[
            'recurrenceFrequency',
            'recurrenceInterval',
            'recurrenceUntilDateKey',
          ],
        ),
      );
    });
    return events.first.id;
  }

  @override
  Future<void> updateEvent({
    required String eventId,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    bool applyToSeries = false,
  }) async {
    _validateDraft(draft);
    final id = eventId.trim();
    if (id.isEmpty) return;
    final current = await readEvent(id);
    if (current == null || current.isDeleted) return;
    if (applyToSeries && current.isRecurring) {
      await _replaceSeriesFromOccurrence(current, draft, actor);
      return;
    }
    final next = _eventFromDraft(
      id: current.id,
      draft: draft,
      actor: actor,
      existing: current,
      forceSeriesId: current.seriesId,
      forceOccurrenceDateKey: current.occurrenceDateKey,
      forceRecurrenceFrequency: current.recurrenceFrequency,
      forceRecurrenceUntilDateKey: current.recurrenceUntilDateKey,
    );
    await _firestore.runTransaction((transaction) async {
      await _applySummaryAdjustments(
        transaction,
        <_SummaryAdjustment>[
          ..._summaryAdjustmentsForEvents(<HeadquarterCalendarEvent>[current], -1),
          ..._summaryAdjustmentsForEvents(<HeadquarterCalendarEvent>[next], 1),
        ],
      );
      transaction.set(_events.doc(id), next.toUpdateMap(), SetOptions(merge: true));
      transaction.set(
        _logs.doc(),
        _logData(
          eventId: id,
          action: 'update',
          actor: actor,
          changedFields: _changedFields(current, next),
        ),
      );
    });
  }

  @override
  Future<void> softDeleteEvent({
    required String eventId,
    required HeadquarterCalendarActor actor,
    bool applyToSeries = false,
  }) async {
    final id = eventId.trim();
    if (id.isEmpty) return;
    final current = await readEvent(id);
    if (current == null || current.isDeleted) return;
    if (applyToSeries && current.isRecurring) {
      final snapshot = await _events
          .where('seriesId', isEqualTo: current.seriesId)
          .where('isDeleted', isEqualTo: false)
          .where('occurrenceDateKey', isGreaterThanOrEqualTo: current.occurrenceDateKey)
          .limit(100)
          .get();
      final events = snapshot.docs
          .map((doc) => HeadquarterCalendarEvent.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      await _firestore.runTransaction((transaction) async {
        await _applySummaryAdjustments(
          transaction,
          _summaryAdjustmentsForEvents(events, -1),
        );
        for (final event in events) {
          transaction.set(
            _events.doc(event.id),
            _deleteMap(actor),
            SetOptions(merge: true),
          );
        }
        transaction.set(
          _series.doc(current.seriesId),
          <String, dynamic>{
            'active': false,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': actor.userId,
            'updatedByName': actor.userName,
          },
          SetOptions(merge: true),
        );
        transaction.set(
          _logs.doc(),
          _logData(
            eventId: current.seriesId,
            action: 'deleteSeriesFromOccurrence',
            actor: actor,
            changedFields: const <String>['isDeleted'],
          ),
        );
      });
      return;
    }
    await _firestore.runTransaction((transaction) async {
      await _applySummaryAdjustments(
        transaction,
        _summaryAdjustmentsForEvents(<HeadquarterCalendarEvent>[current], -1),
      );
      transaction.set(_events.doc(id), _deleteMap(actor), SetOptions(merge: true));
      transaction.set(
        _logs.doc(),
        _logData(
          eventId: id,
          action: 'delete',
          actor: actor,
          changedFields: const <String>['isDeleted', 'deletedAt'],
        ),
      );
    });
  }

  @override
  Future<void> acknowledgeEvent({
    required HeadquarterCalendarEvent event,
    required HeadquarterCalendarActor actor,
  }) async {
    if (event.id.trim().isEmpty || actor.userId.trim().isEmpty) return;
    await _receipts.doc(_receiptDocId(event.id, actor.userId)).set(
      <String, dynamic>{
        'eventId': event.id,
        'userId': actor.userId,
        'userName': actor.userName,
        'division': actor.division,
        'areaName': actor.areaName,
        'readAt': FieldValue.serverTimestamp(),
        'acknowledgedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<Set<String>> readAcknowledgedEventIds({
    required List<String> eventIds,
    required String userId,
  }) async {
    final cleanUser = userId.trim();
    final ids = eventIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleanUser.isEmpty || ids.isEmpty) return <String>{};
    final result = <String>{};
    for (final chunk in _chunks(ids, 10)) {
      final receiptIds = chunk.map((eventId) => _receiptDocId(eventId, cleanUser)).toList();
      final snapshot = await _receipts
          .where(FieldPath.documentId, whereIn: receiptIds)
          .get();
      for (final doc in snapshot.docs) {
        final eventId = doc.data()['eventId'];
        if (eventId is String && eventId.trim().isNotEmpty) result.add(eventId.trim());
      }
    }
    return result;
  }

  @override
  Future<HeadquarterCalendarSearchPage> searchEvents({
    required HeadquarterCalendarSearchQuery query,
    HeadquarterCalendarSearchCursor? cursor,
    int limit = 20,
  }) async {
    final terms = normalizeHeadquarterCalendarSearchText(query.keyword)
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
    Query<Map<String, dynamic>> firestoreQuery = _events
        .where('scopeKey', whereIn: _scopeKeys(query.userId, query.scopeFilter))
        .where('searchTokens', arrayContains: terms.first);
    if (!query.includeDeleted) {
      firestoreQuery = firestoreQuery.where('isDeleted', isEqualTo: false);
    }
    if (query.eventType.isNotEmpty && query.eventType != 'all') {
      firestoreQuery = firestoreQuery.where('eventType', isEqualTo: query.eventType);
    }
    if (query.priority.isNotEmpty && query.priority != 'all') {
      firestoreQuery = firestoreQuery.where('priority', isEqualTo: query.priority);
    }
    if (query.toDate != null) {
      firestoreQuery = firestoreQuery.where(
        'startDateKey',
        isLessThanOrEqualTo: HeadquarterCalendarEvent.dateKeyOf(query.toDate!),
      );
    }
    firestoreQuery = firestoreQuery
        .orderBy('startDateKey', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (cursor != null) {
      firestoreQuery = firestoreQuery.startAfter(<Object>[
        cursor.startDateKey,
        cursor.documentId,
      ]);
    }
    final safeLimit = limit <= 0 ? 20 : limit;
    final snapshot = await firestoreQuery.limit(safeLimit + 1).get();
    final docs = snapshot.docs.take(safeLimit).toList(growable: false);
    final events = docs
        .map((doc) => HeadquarterCalendarEvent.fromMap(doc.id, doc.data()))
        .where((event) => _matchesSearch(event, query, terms))
        .toList(growable: false);
    final last = docs.isEmpty ? null : docs.last;
    return HeadquarterCalendarSearchPage(
      events: events,
      nextCursor: last == null
          ? null
          : HeadquarterCalendarSearchCursor(
              startDateKey: (last.data()['startDateKey'] ?? '').toString(),
              documentId: last.id,
            ),
      hasMore: snapshot.docs.length > safeLimit,
    );
  }

  @override
  Future<HeadquarterCalendarMigrationBatch> migrateLegacyEvents({
    int limit = 50,
  }) async {
    final safeLimit = limit <= 0 ? 50 : math.min(limit, 100);
    final meta = await _migrationMeta.get();
    final metaData = meta.data() ?? <String, dynamic>{};
    if (metaData['legacyMigrationComplete'] == true) {
      return const HeadquarterCalendarMigrationBatch(
        scannedCount: 0,
        updatedCount: 0,
        hasMore: false,
        completed: true,
      );
    }
    final cursor = (metaData['migrationCursor'] ?? '').toString().trim();
    Query<Map<String, dynamic>> query = _events.orderBy(FieldPath.documentId);
    if (cursor.isNotEmpty) query = query.startAfter(<Object>[cursor]);
    final snapshot = await query.limit(safeLimit + 1).get();
    final docs = snapshot.docs.take(safeLimit).toList(growable: false);
    final batch = _firestore.batch();
    var updated = 0;
    for (final doc in docs) {
      final data = doc.data();
      final event = HeadquarterCalendarEvent.fromMap(doc.id, data);
      final tokens = buildHeadquarterCalendarSearchTokens(
        title: event.title,
        description: event.description,
        eventType: '${event.eventType} ${_eventTypeLabel(event.eventType)}',
        priority: '${event.priority} ${_priorityLabel(event.priority)}',
        createdByName: event.createdByName,
        attendeeNames: event.attendeeNames.values,
      );
      final needsUpdate = event.schemaVersion < 2 ||
          event.searchTokenVersion < headquarterCalendarSearchTokenVersion ||
          event.searchTokens.isEmpty ||
          data['dateKeys'] is! Iterable ||
          data['scopeKey'] == null;
      if (needsUpdate) {
        final createdAtValue = data['createdAt'] ?? data['startsAt'];
        batch.set(
          doc.reference,
          <String, dynamic>{
            ...event.copyWith(
              searchTokens: tokens,
              searchTokenVersion: headquarterCalendarSearchTokenVersion,
              schemaVersion: 2,
            ).toCommonMap(),
            if (createdAtValue != null) 'createdAt': createdAtValue,
            if (createdAtValue == null) 'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        updated += 1;
      }
    }
    final completed = snapshot.docs.length <= safeLimit;
    batch.set(
      _migrationMeta,
      <String, dynamic>{
        'migrationCursor': docs.isEmpty ? cursor : docs.last.id,
        'legacyMigrationComplete': completed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return HeadquarterCalendarMigrationBatch(
      scannedCount: docs.length,
      updatedCount: updated,
      hasMore: !completed,
      completed: completed,
    );
  }

  @override
  Future<bool> isLegacyMigrationComplete() async {
    final snapshot = await _migrationMeta.get();
    return snapshot.data()?['legacyMigrationComplete'] == true;
  }

  @override
  Future<List<HeadquarterCalendarStaffMember>> readStaffMembers({
    bool forceRefresh = false,
  }) async {
    final cached = _staffCache;
    final cachedAt = _staffCacheAt;
    if (!forceRefresh && cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    final snapshot = await _firestore.collection('user_accounts').get();
    final result = <HeadquarterCalendarStaffMember>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isActive'] == false) continue;
      final role = (data['role'] ?? '').toString().trim();
      final position = (data['position'] ?? '').toString().trim();
      final divisions = data['divisions'] is Iterable
          ? (data['divisions'] as Iterable).map((value) => value.toString()).toList()
          : const <String>[];
      if (!isHeadquarterCalendarStaffScope(
        role: role,
        position: position,
        division: divisions.join(' '),
      )) continue;
      final areas = data['areas'] is Iterable
          ? (data['areas'] as Iterable).map((value) => value.toString()).toList()
          : const <String>[];
      final currentArea = (data['currentArea'] ?? '').toString().trim();
      result.add(
        HeadquarterCalendarStaffMember(
          id: doc.id,
          name: (data['name'] ?? doc.id).toString().trim(),
          role: role,
          position: position,
          division: divisions.isEmpty ? '' : divisions.first.trim(),
          areaName: currentArea.isNotEmpty
              ? currentArea
              : areas.isEmpty
                  ? ''
                  : areas.first.trim(),
        ),
      );
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    _staffCache = List<HeadquarterCalendarStaffMember>.unmodifiable(result);
    _staffCacheAt = DateTime.now();
    return _staffCache!;
  }

  @override
  Future<void> setAttendanceStatus({
    required HeadquarterCalendarEvent event,
    required HeadquarterCalendarActor actor,
    required String status,
  }) async {
    final cleanStatus = status.trim();
    if (!const <String>{'attending', 'declined', 'tentative'}.contains(cleanStatus)) {
      throw ArgumentError.value(status, 'status');
    }
    final userId = actor.userId.trim();
    if (userId.isEmpty) {
      throw StateError('참석 응답 사용자 정보가 없습니다.');
    }
    final isTarget = event.attendeeMode == 'all'
        ? event.attendeeIds.isEmpty || event.attendeeIds.contains(userId)
        : event.attendeeMode == 'selected'
            ? event.attendeeIds.contains(userId)
            : false;
    if (!isTarget) {
      throw StateError('이 일정의 참석 응답 대상이 아닙니다.');
    }
    await _attendance.doc(_attendanceDocId(event.id, userId)).set(
      <String, dynamic>{
        'eventId': event.id,
        'userId': userId,
        'userName': actor.userName,
        'division': actor.division,
        'areaName': actor.areaName,
        'status': cleanStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<List<HeadquarterCalendarReceipt>> readReceipts({
    required String eventId,
  }) async {
    final snapshot = await _receipts
        .where('eventId', isEqualTo: eventId.trim())
        .orderBy('acknowledgedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => HeadquarterCalendarReceipt.fromMap(doc.data()))
        .toList(growable: false);
  }

  @override
  Future<List<HeadquarterCalendarAttendanceResponse>> readAttendanceResponses({
    required String eventId,
  }) async {
    final snapshot = await _attendance
        .where('eventId', isEqualTo: eventId.trim())
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => HeadquarterCalendarAttendanceResponse.fromMap(doc.data()))
        .toList(growable: false);
  }

  Query<Map<String, dynamic>> _modernDateQuery(
    String dateKey,
    String userId,
    String scopeFilter,
  ) {
    return _events
        .where('isDeleted', isEqualTo: false)
        .where('scopeKey', whereIn: _scopeKeys(userId, scopeFilter))
        .where('dateKeys', arrayContains: dateKey)
        .orderBy('priorityRank', descending: true)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
  }

  List<String> _scopeKeys(String userId, String filter) {
    final cleanUser = userId.trim();
    if (filter == 'company') return const <String>['company'];
    if (filter == 'personal') {
      return cleanUser.isEmpty ? const <String>['company'] : <String>['user:$cleanUser'];
    }
    return cleanUser.isEmpty
        ? const <String>['company']
        : <String>['company', 'user:$cleanUser'];
  }

  List<HeadquarterCalendarEvent> _eventsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map((doc) => HeadquarterCalendarEvent.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }

  HeadquarterCalendarEventPage _eventPage(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int limit,
  ) {
    final selected = docs.take(limit).toList(growable: false);
    final events = selected
        .map((doc) => HeadquarterCalendarEvent.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    final last = selected.isEmpty ? null : selected.last;
    final data = last?.data();
    final createdAt = data?['createdAt'];
    return HeadquarterCalendarEventPage(
      events: events,
      nextCursor: last == null
          ? null
          : HeadquarterCalendarEventCursor(
              priorityRank: _readInt(data?['priorityRank'], fallback: 1),
              createdAtMillis: createdAt is Timestamp
                  ? createdAt.millisecondsSinceEpoch
                  : DateTime.fromMillisecondsSinceEpoch(0).millisecondsSinceEpoch,
              documentId: last.id,
            ),
      hasMore: docs.length > limit,
    );
  }

  Stream<HeadquarterCalendarMonthSummary> _combineSummaryStreams(
    Stream<HeadquarterCalendarMonthSummary> company,
    Stream<HeadquarterCalendarMonthSummary> personal,
  ) {
    late StreamController<HeadquarterCalendarMonthSummary> controller;
    StreamSubscription<HeadquarterCalendarMonthSummary>? leftSub;
    StreamSubscription<HeadquarterCalendarMonthSummary>? rightSub;
    HeadquarterCalendarMonthSummary? left;
    HeadquarterCalendarMonthSummary? right;
    void emit() {
      final a = left;
      final b = right;
      if (a == null || b == null || controller.isClosed) return;
      controller.add(a.merge(b));
    }
    controller = StreamController<HeadquarterCalendarMonthSummary>(
      onListen: () {
        leftSub = company.listen((value) {
          left = value;
          emit();
        }, onError: controller.addError);
        rightSub = personal.listen((value) {
          right = value;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await leftSub?.cancel();
        await rightSub?.cancel();
      },
    );
    return controller.stream;
  }

  HeadquarterCalendarEvent _eventFromDraft({
    required String id,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    required HeadquarterCalendarEvent? existing,
    String? forceSeriesId,
    String? forceOccurrenceDateKey,
    String? forceRecurrenceFrequency,
    String? forceRecurrenceUntilDateKey,
  }) {
    final start = HeadquarterCalendarEvent.dateOnly(draft.startDate);
    final rawEnd = HeadquarterCalendarEvent.dateOnly(draft.endDate);
    final end = rawEnd.isBefore(start) ? start : rawEnd;
    final dates = HeadquarterCalendarEvent.dateKeysBetween(start, end);
    final priority = draft.priority.trim().isEmpty ? 'normal' : draft.priority.trim();
    final tokens = buildHeadquarterCalendarSearchTokens(
      title: draft.title,
      description: draft.description,
      eventType: '${draft.eventType} ${_eventTypeLabel(draft.eventType)}',
      priority: '$priority ${_priorityLabel(priority)}',
      createdByName: existing?.createdByName ?? actor.userName,
      attendeeNames: draft.attendeeNames.values,
    );
    return HeadquarterCalendarEvent(
      id: id,
      title: draft.title.trim().isEmpty ? '제목 없음' : draft.title.trim(),
      description: draft.description.trim(),
      startDate: start,
      endDate: end,
      startDateKey: HeadquarterCalendarEvent.dateKeyOf(start),
      endDateKey: HeadquarterCalendarEvent.dateKeyOf(end),
      dateKeys: dates,
      monthKeys: HeadquarterCalendarEvent.monthKeysForDateKeys(dates),
      scopeKey: _normalizedScopeKey(
        draft.scopeKey,
        draft.ownerUserId,
        actor.userId,
      ),
      ownerUserId: _normalizedOwnerUserId(
        draft.scopeKey,
        draft.ownerUserId,
        actor.userId,
      ),
      eventType: draft.eventType.trim().isEmpty ? 'notice' : draft.eventType.trim(),
      priority: priority,
      priorityRank: HeadquarterCalendarEvent.priorityRankOf(priority),
      createdBy: existing?.createdBy ?? actor.userId,
      createdByName: existing?.createdByName ?? actor.userName,
      updatedBy: actor.userId,
      updatedByName: actor.userName,
      createdAt: existing?.createdAt,
      updatedAt: existing?.updatedAt,
      deletedAt: existing?.deletedAt,
      isDeleted: false,
      requiresAck: draft.requiresAck,
      seriesId: forceSeriesId ?? '',
      occurrenceDateKey: forceOccurrenceDateKey ?? '',
      recurrenceFrequency: forceRecurrenceFrequency ?? draft.recurrenceFrequency,
      recurrenceInterval: draft.recurrenceInterval.clamp(1, 4).toInt(),
      recurrenceUntilDateKey: forceRecurrenceUntilDateKey ??
          HeadquarterCalendarEvent.dateKeyOf(draft.recurrenceUntilDate),
      attendeeMode: draft.attendeeMode,
      attendeeIds: List<String>.unmodifiable(draft.attendeeIds.toSet()),
      attendeeNames: Map<String, String>.unmodifiable(draft.attendeeNames),
      targetCountSnapshot: draft.targetCountSnapshot,
      searchTokens: tokens,
      searchTokenVersion: headquarterCalendarSearchTokenVersion,
      schemaVersion: 2,
    );
  }

  List<HeadquarterCalendarEvent> _eventsForRecurrence({
    required String seriesId,
    required HeadquarterCalendarEventDraft draft,
    required HeadquarterCalendarActor actor,
    required String? existingCreatedBy,
    required String? existingCreatedByName,
  }) {
    final starts = _recurrenceStarts(draft);
    final duration = math.max(0, HeadquarterCalendarEvent.dateOnly(draft.endDate)
        .difference(HeadquarterCalendarEvent.dateOnly(draft.startDate)).inDays);
    return starts.map((start) {
      final occurrenceDraft = HeadquarterCalendarEventDraft(
        title: draft.title,
        description: draft.description,
        startDate: start,
        endDate: start.add(Duration(days: duration)),
        scopeKey: draft.scopeKey,
        ownerUserId: draft.ownerUserId,
        eventType: draft.eventType,
        priority: draft.priority,
        requiresAck: draft.requiresAck,
        recurrenceFrequency: draft.recurrenceFrequency,
        recurrenceInterval: draft.recurrenceInterval,
        recurrenceUntilDate: draft.recurrenceUntilDate,
        attendeeMode: draft.attendeeMode,
        attendeeIds: draft.attendeeIds,
        attendeeNames: draft.attendeeNames,
        targetCountSnapshot: draft.targetCountSnapshot,
      );
      final key = HeadquarterCalendarEvent.dateKeyOf(start);
      final event = _eventFromDraft(
        id: _occurrenceId(seriesId, key),
        draft: occurrenceDraft,
        actor: actor,
        existing: existingCreatedBy == null
            ? null
            : _createdIdentityEvent(existingCreatedBy, existingCreatedByName ?? ''),
        forceSeriesId: seriesId,
        forceOccurrenceDateKey: key,
        forceRecurrenceFrequency: draft.recurrenceFrequency,
        forceRecurrenceUntilDateKey: HeadquarterCalendarEvent.dateKeyOf(draft.recurrenceUntilDate),
      );
      return event;
    }).toList(growable: false);
  }

  HeadquarterCalendarEvent _createdIdentityEvent(String userId, String name) {
    final now = DateTime.now();
    return HeadquarterCalendarEvent(
      id: '', title: '', description: '', startDate: now, endDate: now,
      startDateKey: '', endDateKey: '', dateKeys: const <String>[], monthKeys: const <String>[],
      scopeKey: 'company', ownerUserId: '', eventType: 'notice', priority: 'normal', priorityRank: 1,
      createdBy: userId, createdByName: name, updatedBy: '', updatedByName: '', createdAt: null,
      updatedAt: null, deletedAt: null, isDeleted: false, requiresAck: false, seriesId: '',
      occurrenceDateKey: '', recurrenceFrequency: 'none', recurrenceInterval: 1,
      recurrenceUntilDateKey: '', attendeeMode: 'none', attendeeIds: const <String>[],
      attendeeNames: const <String, String>{}, targetCountSnapshot: 0,
      searchTokens: const <String>[], searchTokenVersion: 0, schemaVersion: 2,
    );
  }

  List<DateTime> _recurrenceStarts(HeadquarterCalendarEventDraft draft) {
    final start = HeadquarterCalendarEvent.dateOnly(draft.startDate);
    var until = HeadquarterCalendarEvent.dateOnly(draft.recurrenceUntilDate);
    final maxUntil = DateTime(start.year + 1, start.month, start.day)
        .subtract(const Duration(days: 1));
    if (until.isAfter(maxUntil)) until = maxUntil;
    if (until.isBefore(start)) until = start;
    final interval = draft.recurrenceInterval.clamp(1, 4).toInt();
    final values = <DateTime>[];
    var current = start;
    while (!current.isAfter(until) && values.length < 60) {
      values.add(current);
      if (draft.recurrenceFrequency == 'monthly') {
        current = _addMonthsKeepingDay(current, interval);
      } else {
        current = current.add(Duration(days: 7 * interval));
      }
    }
    return values;
  }

  DateTime _addMonthsKeepingDay(DateTime date, int months) {
    final targetFirst = DateTime(date.year, date.month + months, 1);
    final lastDay = DateTime(targetFirst.year, targetFirst.month + 1, 0).day;
    return DateTime(targetFirst.year, targetFirst.month, math.min(date.day, lastDay));
  }

  Future<void> _replaceSeriesFromOccurrence(
    HeadquarterCalendarEvent current,
    HeadquarterCalendarEventDraft draft,
    HeadquarterCalendarActor actor,
  ) async {
    final snapshot = await _events
        .where('seriesId', isEqualTo: current.seriesId)
        .where('isDeleted', isEqualTo: false)
        .where('occurrenceDateKey', isGreaterThanOrEqualTo: current.occurrenceDateKey)
        .limit(100)
        .get();
    final oldEvents = snapshot.docs
        .map((doc) => HeadquarterCalendarEvent.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    final nextDraft = HeadquarterCalendarEventDraft(
      title: draft.title,
      description: draft.description,
      startDate: draft.startDate,
      endDate: draft.endDate,
      scopeKey: draft.scopeKey,
      ownerUserId: draft.ownerUserId,
      eventType: draft.eventType,
      priority: draft.priority,
      requiresAck: draft.requiresAck,
      recurrenceFrequency: draft.recurrenceFrequency == 'none'
          ? current.recurrenceFrequency
          : draft.recurrenceFrequency,
      recurrenceInterval: draft.recurrenceInterval,
      recurrenceUntilDate: draft.recurrenceUntilDate,
      attendeeMode: draft.attendeeMode,
      attendeeIds: draft.attendeeIds,
      attendeeNames: draft.attendeeNames,
      targetCountSnapshot: draft.targetCountSnapshot,
    );
    final newEvents = _eventsForRecurrence(
      seriesId: current.seriesId,
      draft: nextDraft,
      actor: actor,
      existingCreatedBy: current.createdBy,
      existingCreatedByName: current.createdByName,
    );
    await _firestore.runTransaction((transaction) async {
      await _applySummaryAdjustments(
        transaction,
        <_SummaryAdjustment>[
          ..._summaryAdjustmentsForEvents(oldEvents, -1),
          ..._summaryAdjustmentsForEvents(newEvents, 1),
        ],
      );
      for (final event in oldEvents) {
        transaction.set(_events.doc(event.id), _deleteMap(actor), SetOptions(merge: true));
      }
      for (final event in newEvents) {
        transaction.set(_events.doc(event.id), event.toCreateMap());
      }
      transaction.set(
        _series.doc(current.seriesId),
        _seriesData(current.seriesId, nextDraft, actor),
        SetOptions(merge: true),
      );
      transaction.set(
        _logs.doc(),
        _logData(
          eventId: current.seriesId,
          action: 'replaceSeriesFromOccurrence',
          actor: actor,
          changedFields: const <String>['futureOccurrences'],
        ),
      );
    });
  }

  Map<String, dynamic> _seriesData(
    String seriesId,
    HeadquarterCalendarEventDraft draft,
    HeadquarterCalendarActor actor,
  ) {
    return <String, dynamic>{
      'id': seriesId,
      'title': draft.title.trim(),
      'startDateKey': HeadquarterCalendarEvent.dateKeyOf(draft.startDate),
      'durationDays': HeadquarterCalendarEvent.dateOnly(draft.endDate)
              .difference(HeadquarterCalendarEvent.dateOnly(draft.startDate))
              .inDays +
          1,
      'frequency': draft.recurrenceFrequency,
      'interval': draft.recurrenceInterval.clamp(1, 4).toInt(),
      'untilDateKey': HeadquarterCalendarEvent.dateKeyOf(draft.recurrenceUntilDate),
      'scopeKey': _normalizedScopeKey(
        draft.scopeKey,
        draft.ownerUserId,
        actor.userId,
      ),
      'ownerUserId': _normalizedOwnerUserId(
        draft.scopeKey,
        draft.ownerUserId,
        actor.userId,
      ),
      'active': true,
      'updatedBy': actor.userId,
      'updatedByName': actor.userName,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  void _validateDraft(HeadquarterCalendarEventDraft draft) {
    if (draft.title.trim().isEmpty) throw ArgumentError('일정 제목이 필요합니다.');
    final start = HeadquarterCalendarEvent.dateOnly(draft.startDate);
    final end = HeadquarterCalendarEvent.dateOnly(draft.endDate);
    if (end.isBefore(start)) throw ArgumentError('종료일은 시작일보다 빠를 수 없습니다.');
    if (end.difference(start).inDays > 365) {
      throw ArgumentError('일정 기간은 최대 366일입니다.');
    }
    if (draft.isRecurring &&
        !const <String>{'weekly', 'monthly'}.contains(draft.recurrenceFrequency)) {
      throw ArgumentError('지원하지 않는 반복 유형입니다.');
    }
  }

  List<_SummaryAdjustment> _summaryAdjustmentsForEvents(
    Iterable<HeadquarterCalendarEvent> events,
    int delta,
  ) {
    final result = <_SummaryAdjustment>[];
    for (final event in events) {
      final seenMonths = <String>{};
      for (final dateKey in event.dateKeys) {
        final monthKey = dateKey.substring(0, 7);
        final firstInMonth = seenMonths.add(monthKey);
        result.add(
          _SummaryAdjustment(
            scopeKey: event.scopeKey,
            ownerUserId: event.ownerUserId,
            monthKey: monthKey,
            dateKey: dateKey,
            monthCountDelta: firstInMonth ? delta : 0,
            monthImportantDelta: firstInMonth && event.isImportant ? delta : 0,
            dayCountDelta: delta,
            dayImportantDelta: event.isImportant ? delta : 0,
          ),
        );
      }
    }
    return result;
  }

  Future<void> _applySummaryAdjustments(
    Transaction transaction,
    List<_SummaryAdjustment> adjustments,
  ) async {
    final grouped = <String, List<_SummaryAdjustment>>{};
    for (final adjustment in adjustments) {
      final key = '${adjustment.scopeKey}|${adjustment.ownerUserId}|${adjustment.monthKey}';
      grouped.putIfAbsent(key, () => <_SummaryAdjustment>[]).add(adjustment);
    }
    final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final refs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final entry in grouped.entries) {
      final sample = entry.value.first;
      final ref = _summaryRef(sample.scopeKey, sample.ownerUserId, sample.monthKey);
      refs[entry.key] = ref;
      snapshots[entry.key] = await transaction.get(ref);
    }
    for (final entry in grouped.entries) {
      final sample = entry.value.first;
      final ref = refs[entry.key]!;
      final data = Map<String, dynamic>.from(snapshots[entry.key]!.data() ?? <String, dynamic>{});
      final days = _readMutableMap(data['days']);
      var eventCount = _readInt(data['eventCount']);
      var importantCount = _readInt(data['importantCount']);
      for (final adjustment in entry.value) {
        eventCount = math.max(0, eventCount + adjustment.monthCountDelta);
        importantCount = math.max(0, importantCount + adjustment.monthImportantDelta);
        final day = _readMutableMap(days[adjustment.dateKey]);
        final nextCount = math.max(0, _readInt(day['count']) + adjustment.dayCountDelta);
        final nextImportant = math.max(0, _readInt(day['importantCount']) + adjustment.dayImportantDelta);
        if (nextCount == 0 && nextImportant == 0) {
          days.remove(adjustment.dateKey);
        } else {
          days[adjustment.dateKey] = <String, dynamic>{
            'count': nextCount,
            'importantCount': nextImportant,
          };
        }
      }
      transaction.set(ref, <String, dynamic>{
        'monthKey': sample.monthKey,
        'scopeKey': sample.scopeKey,
        'ownerUserId': sample.ownerUserId,
        'eventCount': eventCount,
        'importantCount': importantCount,
        'days': days,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  DocumentReference<Map<String, dynamic>> _summaryRef(
    String scopeKey,
    String ownerUserId,
    String monthKey,
  ) {
    if (scopeKey.startsWith('user:')) {
      final owner = ownerUserId.isNotEmpty ? ownerUserId : scopeKey.substring(5);
      return _userMonths.doc(_userMonthDocId(owner, monthKey));
    }
    return _months.doc(monthKey);
  }

  Map<String, dynamic> _deleteMap(HeadquarterCalendarActor actor) {
    return <String, dynamic>{
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': actor.userId,
      'updatedByName': actor.userName,
    };
  }

  bool _matchesSearch(
    HeadquarterCalendarEvent event,
    HeadquarterCalendarSearchQuery query,
    List<String> terms,
  ) {
    if (query.eventType.isNotEmpty && query.eventType != 'all' && event.eventType != query.eventType) {
      return false;
    }
    if (query.priority.isNotEmpty && query.priority != 'all' && event.priority != query.priority) {
      return false;
    }
    if (query.fromDate != null && event.endDate.isBefore(HeadquarterCalendarEvent.dateOnly(query.fromDate!))) {
      return false;
    }
    if (query.toDate != null && event.startDate.isAfter(HeadquarterCalendarEvent.dateOnly(query.toDate!))) {
      return false;
    }
    final source = normalizeHeadquarterCalendarSearchText(
      '${event.title} ${event.description} ${event.createdByName} ${event.attendeeNames.values.join(' ')}',
    );
    return terms.every(source.contains);
  }

  Map<String, dynamic> _logData({
    required String eventId,
    required String action,
    required HeadquarterCalendarActor actor,
    required List<String> changedFields,
  }) {
    return <String, dynamic>{
      'eventId': eventId,
      'action': action,
      'actorUserId': actor.userId,
      'actorName': actor.userName,
      'actorRole': actor.role,
      'createdAt': FieldValue.serverTimestamp(),
      'changedFields': changedFields,
    };
  }

  List<String> _changedFields(
    HeadquarterCalendarEvent before,
    HeadquarterCalendarEvent after,
  ) {
    final fields = <String>[];
    if (before.title != after.title) fields.add('title');
    if (before.description != after.description) fields.add('description');
    if (before.startDateKey != after.startDateKey) fields.add('startDateKey');
    if (before.endDateKey != after.endDateKey) fields.add('endDateKey');
    if (before.scopeKey != after.scopeKey) fields.add('scopeKey');
    if (before.eventType != after.eventType) fields.add('eventType');
    if (before.priority != after.priority) fields.add('priority');
    if (before.requiresAck != after.requiresAck) fields.add('requiresAck');
    if (before.attendeeMode != after.attendeeMode) fields.add('attendeeMode');
    if (before.attendeeIds.join('|') != after.attendeeIds.join('|')) fields.add('attendeeIds');
    return fields.isEmpty ? const <String>['updatedAt'] : fields;
  }


  String _normalizedScopeKey(
    String scopeKey,
    String ownerUserId,
    String actorUserId,
  ) {
    final cleanScope = scopeKey.trim();
    final owner = _normalizedOwnerUserId(
      cleanScope,
      ownerUserId,
      actorUserId,
    );
    if (cleanScope == 'personal' || cleanScope.startsWith('user:')) {
      return owner.isEmpty ? 'company' : 'user:$owner';
    }
    return 'company';
  }

  String _normalizedOwnerUserId(
    String scopeKey,
    String ownerUserId,
    String actorUserId,
  ) {
    final cleanScope = scopeKey.trim();
    if (cleanScope.startsWith('user:')) {
      final embedded = cleanScope.substring(5).trim();
      if (embedded.isNotEmpty) return embedded;
    }
    if (cleanScope != 'personal') return '';
    final owner = ownerUserId.trim();
    if (owner.isNotEmpty) return owner;
    return actorUserId.trim();
  }

  String _eventTypeLabel(String value) {
    switch (value) {
      case 'meeting':
        return '회의';
      case 'deadline':
        return '마감';
      case 'inspection':
        return '점검';
      case 'education':
        return '교육';
      case 'settlement':
        return '정산';
      case 'urgent':
        return '긴급';
      case 'holiday':
        return '휴무';
      default:
        return '공지';
    }
  }

  String _priorityLabel(String value) {
    switch (value) {
      case 'urgent':
        return '긴급';
      case 'high':
        return '중요';
      default:
        return '일반';
    }
  }

  String _occurrenceId(String seriesId, String dateKey) {
    return '${seriesId}_${dateKey.replaceAll('-', '')}';
  }

  String _receiptDocId(String eventId, String userId) {
    return '${eventId}_${_encoded(userId)}';
  }

  String _attendanceDocId(String eventId, String userId) {
    return '${eventId}_${_encoded(userId)}';
  }

  String _encoded(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  String _userMonthDocId(String userId, String monthKey) {
    return '${_encoded(userId)}_$monthKey';
  }

  List<List<String>> _chunks(List<String> values, int size) {
    final result = <List<String>>[];
    for (var i = 0; i < values.length; i += size) {
      result.add(values.sublist(i, math.min(values.length, i + size)));
    }
    return result;
  }

  Map<String, dynamic> _readMutableMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((key, val) => MapEntry(key.toString(), val)),
      );
    }
    return <String, dynamic>{};
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }
}

class _SummaryAdjustment {
  const _SummaryAdjustment({
    required this.scopeKey,
    required this.ownerUserId,
    required this.monthKey,
    required this.dateKey,
    required this.monthCountDelta,
    required this.monthImportantDelta,
    required this.dayCountDelta,
    required this.dayImportantDelta,
  });

  final String scopeKey;
  final String ownerUserId;
  final String monthKey;
  final String dateKey;
  final int monthCountDelta;
  final int monthImportantDelta;
  final int dayCountDelta;
  final int dayImportantDelta;
}
