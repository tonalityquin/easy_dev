class HeadquarterCalendarDaySummary {
  const HeadquarterCalendarDaySummary({
    required this.dateKey,
    required this.count,
    required this.importantCount,
  });

  final String dateKey;
  final int count;
  final int importantCount;

  bool get hasEvents => count > 0;
  bool get hasImportantEvents => importantCount > 0;
}

class HeadquarterCalendarMonthSummary {
  const HeadquarterCalendarMonthSummary({
    required this.monthKey,
    required this.days,
    required this.eventCount,
    required this.importantCount,
  });

  final String monthKey;
  final Map<String, HeadquarterCalendarDaySummary> days;
  final int eventCount;
  final int importantCount;

  factory HeadquarterCalendarMonthSummary.empty(String monthKey) {
    return HeadquarterCalendarMonthSummary(
      monthKey: monthKey,
      days: const <String, HeadquarterCalendarDaySummary>{},
      eventCount: 0,
      importantCount: 0,
    );
  }

  HeadquarterCalendarMonthSummary merge(
    HeadquarterCalendarMonthSummary other,
  ) {
    final merged = <String, HeadquarterCalendarDaySummary>{};
    final keys = <String>{...days.keys, ...other.days.keys};
    for (final key in keys) {
      final left = day(key);
      final right = other.day(key);
      merged[key] = HeadquarterCalendarDaySummary(
        dateKey: key,
        count: left.count + right.count,
        importantCount: left.importantCount + right.importantCount,
      );
    }
    return HeadquarterCalendarMonthSummary(
      monthKey: monthKey.isNotEmpty ? monthKey : other.monthKey,
      days: Map<String, HeadquarterCalendarDaySummary>.unmodifiable(merged),
      eventCount: eventCount + other.eventCount,
      importantCount: importantCount + other.importantCount,
    );
  }

  HeadquarterCalendarDaySummary day(String dateKey) {
    return days[dateKey] ??
        HeadquarterCalendarDaySummary(
          dateKey: dateKey,
          count: 0,
          importantCount: 0,
        );
  }


}
