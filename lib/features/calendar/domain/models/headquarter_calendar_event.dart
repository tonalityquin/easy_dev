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
  final List<String> searchTokens;
  final int searchTokenVersion;
  final int schemaVersion;

  bool get isImportant => importantFor(
        requiresAck: requiresAck,
        priority: priority,
      );

  bool get isActive => !isDeleted;
  bool get isRecurring => seriesId.trim().isNotEmpty;
  bool get isSingleDay => startDateKey == endDateKey;
  int get durationDays => dateKeys.length;
  DateTime get startsAt => startDate;
  DateTime get endsAt => endDateExclusive.subtract(const Duration(seconds: 1));
  DateTime get endDateExclusive => endDate.add(const Duration(days: 1));
  String get dateKey => startDateKey;
  String get monthKey => monthKeys.isEmpty ? monthKeyOf(startDate) : monthKeys.first;
  bool get allDay => true;

  HeadquarterCalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
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
}

class HeadquarterCalendarEventDraft {
  const HeadquarterCalendarEventDraft({
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.eventType,
    required this.priority,
    required this.requiresAck,
    required this.recurrenceFrequency,
    required this.recurrenceInterval,
    required this.recurrenceUntilDate,
  });

  final String title;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final String eventType;
  final String priority;
  final bool requiresAck;
  final String recurrenceFrequency;
  final int recurrenceInterval;
  final DateTime recurrenceUntilDate;

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
