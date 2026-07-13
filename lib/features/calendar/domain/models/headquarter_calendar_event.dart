import 'package:cloud_firestore/cloud_firestore.dart';

class HeadquarterCalendarEvent {
  const HeadquarterCalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.startDateKey,
    required this.endDateKey,
    required this.dateKeys,
    required this.monthKeys,
    required this.scopeKey,
    required this.ownerUserId,
    required this.eventType,
    required this.priority,
    required this.priorityRank,
    required this.createdBy,
    required this.createdByName,
    required this.updatedBy,
    required this.updatedByName,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.isDeleted,
    required this.requiresAck,
    required this.seriesId,
    required this.occurrenceDateKey,
    required this.recurrenceFrequency,
    required this.recurrenceInterval,
    required this.recurrenceUntilDateKey,
    required this.attendeeMode,
    required this.attendeeIds,
    required this.attendeeNames,
    required this.targetCountSnapshot,
    required this.searchTokens,
    required this.searchTokenVersion,
    required this.schemaVersion,
  });

  final String id;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final String startDateKey;
  final String endDateKey;
  final List<String> dateKeys;
  final List<String> monthKeys;
  final String scopeKey;
  final String ownerUserId;
  final String eventType;
  final String priority;
  final int priorityRank;
  final String createdBy;
  final String createdByName;
  final String updatedBy;
  final String updatedByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final bool isDeleted;
  final bool requiresAck;
  final String seriesId;
  final String occurrenceDateKey;
  final String recurrenceFrequency;
  final int recurrenceInterval;
  final String recurrenceUntilDateKey;
  final String attendeeMode;
  final List<String> attendeeIds;
  final Map<String, String> attendeeNames;
  final int targetCountSnapshot;
  final List<String> searchTokens;
  final int searchTokenVersion;
  final int schemaVersion;

  bool get isImportant => importantFor(
        requiresAck: requiresAck,
        priority: priority,
      );

  bool get isActive => !isDeleted;
  bool get isPersonal => scopeKey.startsWith('user:');
  bool get isCompany => !isPersonal;
  bool get isRecurring => seriesId.trim().isNotEmpty;
  bool get isSingleDay => startDateKey == endDateKey;
  int get durationDays => dateKeys.length;
  DateTime get startsAt => startDate;
  DateTime get endsAt => endDateExclusive.subtract(const Duration(seconds: 1));
  DateTime get endDateExclusive => endDate.add(const Duration(days: 1));
  String get dateKey => startDateKey;
  String get monthKey => monthKeys.isEmpty ? monthKeyOf(startDate) : monthKeys.first;
  bool get allDay => true;

  factory HeadquarterCalendarEvent.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final legacyStart = _readDate(data['startsAt']) ?? DateTime.now();
    final legacyEnd = _readDate(data['endsAt']) ?? legacyStart;
    final rawStart = _readDate(data['startDate']) ?? legacyStart;
    final rawEnd = _readDate(data['endDate']) ?? legacyEnd;
    final start = dateOnly(rawStart);
    final endCandidate = dateOnly(rawEnd);
    final end = endCandidate.isBefore(start) ? start : endCandidate;
    final startKey = _string(data['startDateKey']).isNotEmpty
        ? _string(data['startDateKey'])
        : _string(data['dateKey']).isNotEmpty
            ? _string(data['dateKey'])
            : dateKeyOf(start);
    final endKey = _string(data['endDateKey']).isNotEmpty
        ? _string(data['endDateKey'])
        : dateKeyOf(end);
    final dates = _stringList(data['dateKeys']);
    final normalizedDates = dates.isEmpty
        ? dateKeysBetween(start, end)
        : dates;
    final months = _stringList(data['monthKeys']);
    final normalizedMonths = months.isEmpty
        ? monthKeysForDateKeys(normalizedDates)
        : months;
    final priority = _string(data['priority']).isEmpty
        ? 'normal'
        : _string(data['priority']);
    final scope = _string(data['scopeKey']).isEmpty
        ? 'company'
        : _string(data['scopeKey']);
    final owner = _string(data['ownerUserId']).isNotEmpty
        ? _string(data['ownerUserId'])
        : scope.startsWith('user:')
            ? scope.substring(5)
            : '';
    final attendeeNames = <String, String>{};
    final rawNames = data['attendeeNames'];
    if (rawNames is Map) {
      for (final entry in rawNames.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value.toString().trim();
        if (key.isNotEmpty && value.isNotEmpty) attendeeNames[key] = value;
      }
    }

    return HeadquarterCalendarEvent(
      id: _string(data['id']).isEmpty ? id : _string(data['id']),
      title: _string(data['title']).isEmpty ? '제목 없음' : _string(data['title']),
      description: _string(data['description']),
      startDate: start,
      endDate: end,
      startDateKey: startKey,
      endDateKey: endKey,
      dateKeys: List<String>.unmodifiable(normalizedDates),
      monthKeys: List<String>.unmodifiable(normalizedMonths),
      scopeKey: scope,
      ownerUserId: owner,
      eventType: _string(data['eventType']).isEmpty ? 'notice' : _string(data['eventType']),
      priority: priority,
      priorityRank: _readInt(data['priorityRank'], fallback: priorityRankOf(priority)),
      createdBy: _string(data['createdBy']),
      createdByName: _string(data['createdByName']),
      updatedBy: _string(data['updatedBy']),
      updatedByName: _string(data['updatedByName']),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      deletedAt: _readDate(data['deletedAt']),
      isDeleted: data['isDeleted'] == true,
      requiresAck: data['requiresAck'] == true,
      seriesId: _string(data['seriesId']),
      occurrenceDateKey: _string(data['occurrenceDateKey']),
      recurrenceFrequency: _string(data['recurrenceFrequency']).isEmpty
          ? 'none'
          : _string(data['recurrenceFrequency']),
      recurrenceInterval: _readInt(data['recurrenceInterval'], fallback: 1),
      recurrenceUntilDateKey: _string(data['recurrenceUntilDateKey']),
      attendeeMode: _string(data['attendeeMode']).isEmpty
          ? 'none'
          : _string(data['attendeeMode']),
      attendeeIds: List<String>.unmodifiable(_stringList(data['attendeeIds'])),
      attendeeNames: Map<String, String>.unmodifiable(attendeeNames),
      targetCountSnapshot: _readInt(data['targetCountSnapshot']),
      searchTokens: List<String>.unmodifiable(_stringList(data['searchTokens'])),
      searchTokenVersion: _readInt(data['searchTokenVersion']),
      schemaVersion: _readInt(data['schemaVersion'], fallback: 1),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      ...toCommonMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return <String, dynamic>{
      ...toCommonMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toCommonMap() {
    return <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'description': description.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'endDateExclusive': Timestamp.fromDate(endDateExclusive),
      'startsAt': Timestamp.fromDate(startDate),
      'endsAt': Timestamp.fromDate(endDateExclusive.subtract(const Duration(seconds: 1))),
      'startDateKey': startDateKey,
      'endDateKey': endDateKey,
      'dateKey': startDateKey,
      'monthKey': monthKey,
      'dateKeys': dateKeys,
      'monthKeys': monthKeys,
      'allDay': true,
      'scopeKey': scopeKey,
      'ownerUserId': ownerUserId,
      'eventType': eventType,
      'priority': priority,
      'priorityRank': priorityRank,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
      'requiresAck': requiresAck,
      'seriesId': seriesId,
      'occurrenceDateKey': occurrenceDateKey,
      'recurrenceFrequency': recurrenceFrequency,
      'recurrenceInterval': recurrenceInterval,
      'recurrenceUntilDateKey': recurrenceUntilDateKey,
      'attendeeMode': attendeeMode,
      'attendeeIds': attendeeIds,
      'attendeeNames': attendeeNames,
      'targetCountSnapshot': targetCountSnapshot,
      'searchTokens': searchTokens,
      'searchTokenVersion': searchTokenVersion,
      'schemaVersion': schemaVersion,
    };
  }

  HeadquarterCalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? scopeKey,
    String? ownerUserId,
    String? eventType,
    String? priority,
    int? priorityRank,
    String? createdBy,
    String? createdByName,
    String? updatedBy,
    String? updatedByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? isDeleted,
    bool? requiresAck,
    String? seriesId,
    String? occurrenceDateKey,
    String? recurrenceFrequency,
    int? recurrenceInterval,
    String? recurrenceUntilDateKey,
    String? attendeeMode,
    List<String>? attendeeIds,
    Map<String, String>? attendeeNames,
    int? targetCountSnapshot,
    List<String>? searchTokens,
    int? searchTokenVersion,
    int? schemaVersion,
  }) {
    final nextStart = dateOnly(startDate ?? this.startDate);
    final rawEnd = dateOnly(endDate ?? this.endDate);
    final nextEnd = rawEnd.isBefore(nextStart) ? nextStart : rawEnd;
    final nextDateKeys = dateKeysBetween(nextStart, nextEnd);
    return HeadquarterCalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: nextStart,
      endDate: nextEnd,
      startDateKey: dateKeyOf(nextStart),
      endDateKey: dateKeyOf(nextEnd),
      dateKeys: nextDateKeys,
      monthKeys: monthKeysForDateKeys(nextDateKeys),
      scopeKey: scopeKey ?? this.scopeKey,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      eventType: eventType ?? this.eventType,
      priority: priority ?? this.priority,
      priorityRank: priorityRank ?? this.priorityRank,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      requiresAck: requiresAck ?? this.requiresAck,
      seriesId: seriesId ?? this.seriesId,
      occurrenceDateKey: occurrenceDateKey ?? this.occurrenceDateKey,
      recurrenceFrequency: recurrenceFrequency ?? this.recurrenceFrequency,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceUntilDateKey: recurrenceUntilDateKey ?? this.recurrenceUntilDateKey,
      attendeeMode: attendeeMode ?? this.attendeeMode,
      attendeeIds: attendeeIds ?? this.attendeeIds,
      attendeeNames: attendeeNames ?? this.attendeeNames,
      targetCountSnapshot: targetCountSnapshot ?? this.targetCountSnapshot,
      searchTokens: searchTokens ?? this.searchTokens,
      searchTokenVersion: searchTokenVersion ?? this.searchTokenVersion,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  static bool importantFor({
    required bool requiresAck,
    required String priority,
  }) {
    final value = priority.trim().toLowerCase();
    return requiresAck || value == 'high' || value == 'urgent';
  }

  static int priorityRankOf(String priority) {
    switch (priority.trim().toLowerCase()) {
      case 'urgent':
        return 3;
      case 'high':
        return 2;
      default:
        return 1;
    }
  }

  static DateTime dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static String dateKeyOf(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? dateFromKey(String key) {
    final parts = key.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final date = DateTime(y, m, d);
    if (date.year != y || date.month != m || date.day != d) return null;
    return date;
  }

  static String monthKeyOf(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  static List<String> dateKeysBetween(DateTime start, DateTime end) {
    final first = dateOnly(start);
    final last = dateOnly(end);
    if (last.isBefore(first)) return <String>[dateKeyOf(first)];
    final days = last.difference(first).inDays + 1;
    final safeDays = days.clamp(1, 366).toInt();
    return List<String>.generate(
      safeDays,
      (index) => dateKeyOf(first.add(Duration(days: index))),
      growable: false,
    );
  }

  static List<String> monthKeysForDateKeys(List<String> dateKeys) {
    final values = <String>{};
    for (final key in dateKeys) {
      if (key.length >= 7) values.add(key.substring(0, 7));
    }
    final result = values.toList()..sort();
    return result;
  }

  static String _string(dynamic value) {
    if (value is String) return value.trim();
    if (value == null) return '';
    return value.toString().trim();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! Iterable) return <String>[];
    final result = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    return result;
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }

  static int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }
}

class HeadquarterCalendarEventDraft {
  const HeadquarterCalendarEventDraft({
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.scopeKey,
    required this.ownerUserId,
    required this.eventType,
    required this.priority,
    required this.requiresAck,
    required this.recurrenceFrequency,
    required this.recurrenceInterval,
    required this.recurrenceUntilDate,
    required this.attendeeMode,
    required this.attendeeIds,
    required this.attendeeNames,
    required this.targetCountSnapshot,
  });

  final String title;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final String scopeKey;
  final String ownerUserId;
  final String eventType;
  final String priority;
  final bool requiresAck;
  final String recurrenceFrequency;
  final int recurrenceInterval;
  final DateTime recurrenceUntilDate;
  final String attendeeMode;
  final List<String> attendeeIds;
  final Map<String, String> attendeeNames;
  final int targetCountSnapshot;

  bool get isRecurring => recurrenceFrequency != 'none';
}

class HeadquarterCalendarActor {
  const HeadquarterCalendarActor({
    required this.userId,
    required this.userName,
    required this.role,
    required this.division,
    required this.areaName,
  });

  final String userId;
  final String userName;
  final String role;
  final String division;
  final String areaName;
}
