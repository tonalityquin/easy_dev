import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/account/domain/models/user/user_model.dart';
import '../../features/dashboard/applications/common/endtime_reminder_service.dart';

class WorkSchedulePrefs {
  static const String startMapKey = 'startTimeByWeekday';
  static const String endMapKey = 'endTimeByWeekday';
  static const String breakDaysKey = 'breakDays';
  static const String _legacyStartKey = 'startTime';
  static const String _legacyEndKey = 'endTime';
  static const List<String> days = <String>['월', '화', '수', '목', '금', '토', '일'];

  static int dayToWeekdayInt(String day) {
    switch (day.trim()) {
      case '월':
        return DateTime.monday;
      case '화':
        return DateTime.tuesday;
      case '수':
        return DateTime.wednesday;
      case '목':
        return DateTime.thursday;
      case '금':
        return DateTime.friday;
      case '토':
        return DateTime.saturday;
      case '일':
        return DateTime.sunday;
      default:
        return DateTime.monday;
    }
  }

  static String? formatTime(TimeOfDay? time) {
    if (time == null) return null;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static TimeOfDay? parseHHmm(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static Map<String, dynamic> decodeJsonMap(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String encodeDayTimeMap(Map<String, TimeOfDay?> map) {
    final out = <String, String>{};
    for (final day in days) {
      final hhmm = formatTime(map[day]);
      if (hhmm != null) out[day] = hhmm;
    }
    return jsonEncode(out);
  }

  static Map<String, TimeOfDay?> normalizeDayTimeMap(Map<String, TimeOfDay?> map) {
    return <String, TimeOfDay?>{
      for (final day in days) day: map[day],
    };
  }

  static Map<String, TimeOfDay?> readDayTimeMapFromPrefs(
    SharedPreferences prefs,
    String key,
  ) {
    final decoded = decodeJsonMap((prefs.getString(key) ?? '').trim());
    return <String, TimeOfDay?>{
      for (final day in days)
        day: decoded[day] is String ? parseHHmm(decoded[day] as String) : null,
    };
  }

  static bool hasStoredSchedulePrefs(SharedPreferences prefs) {
    return prefs.containsKey(startMapKey) ||
        prefs.containsKey(endMapKey) ||
        prefs.containsKey(_legacyStartKey) ||
        prefs.containsKey(_legacyEndKey);
  }

  static List<String> normalizeDayList(Iterable<String> raw) {
    final set = raw.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    return <String>[
      for (final day in days)
        if (set.contains(day)) day,
      for (final value in set)
        if (!days.contains(value)) value,
    ];
  }

  static List<String> fixedHolidaysFromMaps({
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
  }) {
    final normalizedStart = normalizeDayTimeMap(startByDay);
    final normalizedEnd = normalizeDayTimeMap(endByDay);
    return <String>[
      for (final day in days)
        if (normalizedStart[day] == null && normalizedEnd[day] == null) day,
    ];
  }

  static List<String> readBreakDaysFromPrefs(
    SharedPreferences prefs, {
    Iterable<String> fallback = const <String>[],
  }) {
    if (!prefs.containsKey(breakDaysKey)) {
      return normalizeDayList(fallback);
    }
    return normalizeDayList(prefs.getStringList(breakDaysKey) ?? const <String>[]);
  }

  static bool requiresBreakOnDateFromPrefs(
    SharedPreferences prefs,
    DateTime date, {
    bool defaultWhenUnset = true,
  }) {
    if (!prefs.containsKey(breakDaysKey)) return defaultWhenUnset;
    final index = date.weekday - 1;
    if (index < 0 || index >= days.length) return defaultWhenUnset;
    return readBreakDaysFromPrefs(prefs).contains(days[index]);
  }

  static List<String> inferBreakDaysFromWorkingMap({
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
  }) {
    return <String>[
      for (final day in days)
        if (startByDay[day] != null && endByDay[day] != null) day,
    ];
  }

  static List<String> normalizeBreakDaysForWorkingMap({
    required Iterable<String> breakDays,
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
  }) {
    final breakSet = normalizeDayList(breakDays).toSet();
    final out = <String>[];
    for (final day in days) {
      if (!breakSet.contains(day)) continue;
      if (startByDay[day] == null || endByDay[day] == null) continue;
      out.add(day);
    }
    for (final value in breakSet) {
      if (!days.contains(value)) out.add(value);
    }
    return out;
  }

  static Map<String, TimeOfDay?> _fillLegacyDays(
    TimeOfDay? time, {
    required Set<String> excludedDays,
  }) {
    return <String, TimeOfDay?>{
      for (final day in days) day: excludedDays.contains(day) ? null : time,
    };
  }

  static Future<bool> migrateLegacySchedulePrefs(SharedPreferences prefs) async {
    final hasStartMap = prefs.containsKey(startMapKey);
    final hasEndMap = prefs.containsKey(endMapKey);
    final hasLegacyStart = prefs.containsKey(_legacyStartKey);
    final hasLegacyEnd = prefs.containsKey(_legacyEndKey);
    final excludedDays = (prefs.getStringList('fixedHolidays') ?? const <String>[])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    var changed = false;

    if (!hasStartMap) {
      final startByDay = hasLegacyStart
          ? _fillLegacyDays(
              parseHHmm(prefs.getString(_legacyStartKey)),
              excludedDays: excludedDays,
            )
          : normalizeDayTimeMap(const <String, TimeOfDay?>{});
      await prefs.setString(startMapKey, encodeDayTimeMap(startByDay));
      changed = true;
    }

    if (!hasEndMap) {
      final endByDay = hasLegacyEnd
          ? _fillLegacyDays(
              parseHHmm(prefs.getString(_legacyEndKey)),
              excludedDays: excludedDays,
            )
          : normalizeDayTimeMap(const <String, TimeOfDay?>{});
      await prefs.setString(endMapKey, encodeDayTimeMap(endByDay));
      changed = true;
    }

    if (hasLegacyStart) {
      await prefs.remove(_legacyStartKey);
      changed = true;
    }
    if (hasLegacyEnd) {
      await prefs.remove(_legacyEndKey);
      changed = true;
    }

    final startByDay = readDayTimeMapFromPrefs(prefs, startMapKey);
    final endByDay = readDayTimeMapFromPrefs(prefs, endMapKey);
    final fixedHolidays = fixedHolidaysFromMaps(
      startByDay: startByDay,
      endByDay: endByDay,
    );
    final previousHolidays = normalizeDayList(
      prefs.getStringList('fixedHolidays') ?? const <String>[],
    );
    if (previousHolidays.join('|') != fixedHolidays.join('|')) {
      await prefs.setStringList('fixedHolidays', fixedHolidays);
      changed = true;
    }

    if (changed) {
      debugPrint(
        '[WorkSchedulePrefs] schedule prefs normalized to weekday maps; holidays=${fixedHolidays.length}',
      );
    }
    return changed;
  }

  static Map<String, TimeOfDay?> resolveStartMap(UserModel user) {
    return normalizeDayTimeMap(user.startTimeByWeekday);
  }

  static Map<String, TimeOfDay?> resolveEndMap(UserModel user) {
    return normalizeDayTimeMap(user.endTimeByWeekday);
  }

  static Set<int> workingWeekdaysFromMaps({
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
  }) {
    final out = <int>{};
    for (final day in days) {
      if (startByDay[day] != null && endByDay[day] != null) {
        out.add(dayToWeekdayInt(day));
      }
    }
    return out;
  }

  static Map<int, String> endTimesByWeekdayFromMap({
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
  }) {
    final out = <int, String>{};
    for (final day in days) {
      final start = startByDay[day];
      final hhmm = formatTime(endByDay[day]);
      if (start == null || hhmm == null) continue;
      out[dayToWeekdayInt(day)] = hhmm;
    }
    return out;
  }

  static Future<void> saveScheduleToPrefs({
    required SharedPreferences prefs,
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
    List<String> breakDays = const <String>[],
  }) async {
    final normalizedStart = normalizeDayTimeMap(startByDay);
    final normalizedEnd = normalizeDayTimeMap(endByDay);
    final fixedHolidays = fixedHolidaysFromMaps(
      startByDay: normalizedStart,
      endByDay: normalizedEnd,
    );
    final normalizedBreakDays = normalizeBreakDaysForWorkingMap(
      breakDays: breakDays,
      startByDay: normalizedStart,
      endByDay: normalizedEnd,
    );

    await prefs.setString(startMapKey, encodeDayTimeMap(normalizedStart));
    await prefs.setString(endMapKey, encodeDayTimeMap(normalizedEnd));
    await prefs.remove(_legacyStartKey);
    await prefs.remove(_legacyEndKey);
    await prefs.setStringList('fixedHolidays', fixedHolidays);
    await prefs.setStringList(breakDaysKey, normalizedBreakDays);
  }

  static Future<void> saveUserSchedule({
    required SharedPreferences prefs,
    required UserModel user,
  }) async {
    final startByDay = resolveStartMap(user);
    final endByDay = resolveEndMap(user);
    await saveScheduleToPrefs(
      prefs: prefs,
      startByDay: startByDay,
      endByDay: endByDay,
      breakDays: normalizeBreakDaysForWorkingMap(
        breakDays: user.breakDays,
        startByDay: startByDay,
        endByDay: endByDay,
      ),
    );
  }

  static Future<void> refreshReminderFromPrefs(SharedPreferences prefs) async {
    await migrateLegacySchedulePrefs(prefs);
    final isWorking = prefs.getBool('isWorking') ?? false;
    if (!isWorking) {
      await EndTimeReminderService.instance.cancel();
      return;
    }

    final startByDay = readDayTimeMapFromPrefs(prefs, startMapKey);
    final endByDay = readDayTimeMapFromPrefs(prefs, endMapKey);
    final workingWeekdays = workingWeekdaysFromMaps(
      startByDay: startByDay,
      endByDay: endByDay,
    );
    final endTimesByWeekday = endTimesByWeekdayFromMap(
      startByDay: startByDay,
      endByDay: endByDay,
    );

    if (workingWeekdays.isEmpty || endTimesByWeekday.isEmpty) {
      await EndTimeReminderService.instance.cancel();
      return;
    }

    await EndTimeReminderService.instance.scheduleWeeklyOneHourBeforeByWeekday(
      endTimeHHmmByWeekday: endTimesByWeekday,
      workingWeekdays: workingWeekdays,
    );
  }
}
