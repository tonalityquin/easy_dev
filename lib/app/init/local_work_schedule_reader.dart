import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalClockTime {
  final int hour;
  final int minute;

  const LocalClockTime({
    required this.hour,
    required this.minute,
  });
}

class LocalWorkScheduleDay {
  final LocalClockTime? start;
  final LocalClockTime? end;
  final bool weeklyScheduleAvailable;

  const LocalWorkScheduleDay({
    required this.start,
    required this.end,
    required this.weeklyScheduleAvailable,
  });
}

class LocalWorkScheduleReader {
  LocalWorkScheduleReader._();

  static const String startMapKey = 'startTimeByWeekday';
  static const String endMapKey = 'endTimeByWeekday';
  static const List<String> days = <String>[
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  static LocalWorkScheduleDay readForSessionDate({
    required SharedPreferences prefs,
    required DateTime sessionDate,
  }) {
    final startByDay = _readDayTimeMap(prefs, startMapKey);
    final endByDay = _readDayTimeMap(prefs, endMapKey);
    final hasWeeklyEnd = endByDay.values.any((value) => value != null);

    if (hasWeeklyEnd) {
      final dayLabel = days[sessionDate.weekday - 1];
      return LocalWorkScheduleDay(
        start: startByDay[dayLabel],
        end: endByDay[dayLabel],
        weeklyScheduleAvailable: true,
      );
    }

    return LocalWorkScheduleDay(
      start: parseHHmm(prefs.getString('startTime')),
      end: parseHHmm(prefs.getString('endTime')),
      weeklyScheduleAvailable: false,
    );
  }

  static LocalClockTime? parseHHmm(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return LocalClockTime(hour: hour, minute: minute);
  }

  static Map<String, LocalClockTime?> _readDayTimeMap(
    SharedPreferences prefs,
    String key,
  ) {
    final decoded = _decodeJsonMap((prefs.getString(key) ?? '').trim());
    final result = <String, LocalClockTime?>{};
    for (final day in days) {
      final raw = decoded[day];
      result[day] = raw is String ? parseHHmm(raw) : null;
    }
    return result;
  }

  static Map<String, dynamic> _decodeJsonMap(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
}
