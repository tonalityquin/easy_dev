import '../domain/monthly_parking_options.dart';

class MonthlyDateRangeCalculator {
  const MonthlyDateRangeCalculator._();

  static DateTime normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime addMonths(DateTime date, int months) {
    final year = date.year + ((date.month - 1 + months) ~/ 12);
    final month = ((date.month - 1 + months) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  static DateTime calculateMonthlyEndDate({
    required DateTime startDate,
    required int duration,
  }) {
    final normalizedStart = normalizeDate(startDate);
    final safeDuration = duration <= 0 ? 1 : duration;
    final anchor = addMonths(normalizedStart, safeDuration);
    if (anchor.day != normalizedStart.day) return anchor;
    return anchor.subtract(const Duration(days: 1));
  }

  static DateTime nextSaturdayOnOrAfter(DateTime date) {
    final normalized = normalizeDate(date);
    if (normalized.weekday == DateTime.saturday) return normalized;
    final daysUntilSaturday = (DateTime.saturday - normalized.weekday + 7) % 7;
    return normalized.add(Duration(days: daysUntilSaturday));
  }

  static DateTime normalizeStartDate({
    required DateTime startDate,
    String? regularType,
  }) {
    final normalized = normalizeDate(startDate);
    if (MonthlyParkingOptions.isWeekendType(regularType)) {
      return nextSaturdayOnOrAfter(normalized);
    }
    return normalized;
  }

  static DateTime calculateEndDate({
    required DateTime startDate,
    required int duration,
    required String periodUnit,
    String? regularType,
  }) {
    final safeDuration = duration <= 0 ? 1 : duration;
    final normalizedStart = normalizeStartDate(
      startDate: startDate,
      regularType: regularType,
    );

    if (MonthlyParkingOptions.isWeekendType(regularType)) {
      return normalizedStart.add(Duration(days: ((safeDuration - 1) * 7) + 1));
    }

    switch (periodUnit.trim()) {
      case '일':
        return normalizedStart.add(Duration(days: safeDuration - 1));
      case '주':
        return normalizedStart.add(Duration(days: safeDuration * 7 - 1));
      case '월':
        return calculateMonthlyEndDate(
          startDate: normalizedStart,
          duration: safeDuration,
        );
      default:
        throw ArgumentError('지원하지 않는 기간 단위입니다: $periodUnit');
    }
  }

  static DateTime calculateNextStartDate(
    DateTime currentEndDate, {
    String? regularType,
  }) {
    final next = normalizeDate(currentEndDate.add(const Duration(days: 1)));
    if (MonthlyParkingOptions.isWeekendType(regularType)) {
      return nextSaturdayOnOrAfter(next);
    }
    return next;
  }

  static DateTime calculateNextEndDate({
    required DateTime currentEndDate,
    required int duration,
    required String periodUnit,
    String? regularType,
  }) {
    final nextStart = calculateNextStartDate(
      currentEndDate,
      regularType: regularType,
    );
    return calculateEndDate(
      startDate: nextStart,
      duration: duration,
      periodUnit: periodUnit,
      regularType: regularType,
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
    final s = normalizeDate(start);
    final e = normalizeDate(end);
    return e.difference(s).inDays + 1;
  }
}
