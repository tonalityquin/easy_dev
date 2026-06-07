class MonthlyDateRangeCalculator {
  const MonthlyDateRangeCalculator._();

  static DateTime addMonths(DateTime date, int months) {
    final year = date.year + ((date.month - 1 + months) ~/ 12);
    final month = ((date.month - 1 + months) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  static DateTime calculateEndDate({
    required DateTime startDate,
    required int duration,
    required String periodUnit,
  }) {
    if (duration <= 0) return startDate;
    switch (periodUnit) {
      case '일':
        return startDate.add(Duration(days: duration - 1));
      case '주':
        return startDate.add(Duration(days: duration * 7 - 1));
      case '월':
      default:
        return addMonths(startDate, duration).subtract(const Duration(days: 1));
    }
  }

  static DateTime calculateNextStartDate(DateTime currentEndDate) {
    return currentEndDate.add(const Duration(days: 1));
  }

  static DateTime calculateNextEndDate({
    required DateTime currentEndDate,
    required int duration,
    required String periodUnit,
  }) {
    final nextStart = calculateNextStartDate(currentEndDate);
    return calculateEndDate(
      startDate: nextStart,
      duration: duration,
      periodUnit: periodUnit,
    );
  }

  static String format(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? parseStrict(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static DateTime? composeStrict({
    required int? year,
    required int? month,
    required int? day,
  }) {
    if (year == null || month == null || day == null) return null;
    if (year < 1900 || year > 2200) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static int daysBetweenInclusive(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return e.difference(s).inDays + 1;
  }
}
