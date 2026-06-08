import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/account/domain/models/user/user_model.dart';
import '../../features/dashboard/applications/common/endtime_reminder_service.dart';

class WorkSchedulePrefs {
  static const String startMapKey = 'startTimeByWeekday';
  static const String endMapKey = 'endTimeByWeekday';
  static const String breakDaysKey = 'breakDays';
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
      final value = map[day];
      final hhmm = formatTime(value);
      if (hhmm == null) continue;
      out[day] = hhmm;
    }
    return jsonEncode(out);
  }

  static Map<String, TimeOfDay?> normalizeDayTimeMap(Map<String, TimeOfDay?> map) {
    final out = <String, TimeOfDay?>{};
    for (final day in days) {
      out[day] = map[day];
    }
    return out;
  }

  static Map<String, TimeOfDay?> readDayTimeMapFromPrefs(
    SharedPreferences prefs,
    String key,
  ) {
    final decoded = decodeJsonMap((prefs.getString(key) ?? '').trim());
    final out = <String, TimeOfDay?>{};
    for (final day in days) {
      final raw = decoded[day];
      if (raw is String) {
        out[day] = parseHHmm(raw);
      } else {
        out[day] = null;
      }
    }
    return out;
  }


  static List<String> normalizeDayList(Iterable<String> raw) {
    final set = raw.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    final out = <String>[
      for (final day in days)
        if (set.contains(day)) day,
      for (final value in set)
        if (!days.contains(value)) value,
    ];
    return out;
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
    final out = <String>[];
    for (final day in days) {
      if (startByDay[day] != null && endByDay[day] != null) {
        out.add(day);
      }
    }
    return out;
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

  static Map<String, TimeOfDay?> fillAllDays(
    TimeOfDay? time, {
    Set<String> excludedDays = const <String>{},
  }) {
    final out = <String, TimeOfDay?>{};
    for (final day in days) {
      out[day] = excludedDays.contains(day) ? null : time;
    }
    return out;
  }

  static TimeOfDay? pickRepresentative(Map<String, TimeOfDay?> map) {
    final weekdayNow = DateTime.now().weekday;
    final today = days[weekdayNow - 1];
    final todayValue = map[today];
    if (todayValue != null) return todayValue;
    for (final day in days) {
      final value = map[day];
      if (value != null) return value;
    }
    return null;
  }

  static Map<String, TimeOfDay?> resolveStartMap(UserModel user) {
    final map = normalizeDayTimeMap(user.startTimeByWeekday);
    final hasWeekly = map.values.any((value) => value != null);
    if (hasWeekly) return map;
    final offDays = user.fixedHolidays.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    return fillAllDays(user.startTime, excludedDays: offDays);
  }

  static Map<String, TimeOfDay?> resolveEndMap(UserModel user) {
    final map = normalizeDayTimeMap(user.endTimeByWeekday);
    final hasWeekly = map.values.any((value) => value != null);
    if (hasWeekly) return map;
    final offDays = user.fixedHolidays.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    return fillAllDays(user.endTime, excludedDays: offDays);
  }

  static Set<int> workingWeekdaysFromMaps({
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
  }) {
    final out = <int>{};
    for (final day in days) {
      final start = startByDay[day];
      final end = endByDay[day];
      if (start != null && end != null) {
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
      final end = endByDay[day];
      final hhmm = formatTime(end);
      if (start == null || hhmm == null) continue;
      out[dayToWeekdayInt(day)] = hhmm;
    }
    return out;
  }

  static Future<void> saveScheduleToPrefs({
    required SharedPreferences prefs,
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
    List<String> fixedHolidays = const <String>[],
    List<String> breakDays = const <String>[],
  }) async {
    final normalizedStart = normalizeDayTimeMap(startByDay);
    final normalizedEnd = normalizeDayTimeMap(endByDay);

    await prefs.setString(startMapKey, encodeDayTimeMap(normalizedStart));
    await prefs.setString(endMapKey, encodeDayTimeMap(normalizedEnd));
    await prefs.setString('startTime', formatTime(pickRepresentative(normalizedStart)) ?? '');
    await prefs.setString('endTime', formatTime(pickRepresentative(normalizedEnd)) ?? '');
    await prefs.setStringList('fixedHolidays', normalizeDayList(fixedHolidays));
    await prefs.setStringList(breakDaysKey, normalizeDayList(breakDays));
  }

  static Future<void> saveUserSchedule({
    required SharedPreferences prefs,
    required UserModel user,
  }) async {
    await saveScheduleToPrefs(
      prefs: prefs,
      startByDay: resolveStartMap(user),
      endByDay: resolveEndMap(user),
      fixedHolidays: user.fixedHolidays,
      breakDays: normalizeBreakDaysForWorkingMap(
        breakDays: user.breakDays,
        startByDay: resolveStartMap(user),
        endByDay: resolveEndMap(user),
      ),
    );
  }

  static Future<void> refreshReminderFromPrefs(SharedPreferences prefs) async {
    final isWorking = prefs.getBool('isWorking') ?? false;
    if (!isWorking) {
      await EndTimeReminderService.instance.cancel();
      return;
    }

    final startByDay = readDayTimeMapFromPrefs(prefs, startMapKey);
    final endByDay = readDayTimeMapFromPrefs(prefs, endMapKey);
    final hasWeekly = startByDay.values.any((value) => value != null) ||
        endByDay.values.any((value) => value != null);

    if (hasWeekly) {
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
      return;
    }

    final legacyEnd = (prefs.getString('endTime') ?? '').trim();
    if (legacyEnd.isEmpty) {
      await EndTimeReminderService.instance.cancel();
      return;
    }

    final fixedHolidays = prefs.getStringList('fixedHolidays') ?? const <String>[];
    if (fixedHolidays.isNotEmpty) {
      await EndTimeReminderService.instance.scheduleWeeklyOneHourBefore(
        endTimeHHmm: legacyEnd,
        fixedHolidays: fixedHolidays,
      );
      return;
    }

    final everyDay = <int>{
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    };
    final endTimeHHmmByWeekday = <int, String>{
      for (final weekday in everyDay) weekday: legacyEnd,
    };

    await EndTimeReminderService.instance.scheduleWeeklyOneHourBeforeByWeekday(
      endTimeHHmmByWeekday: endTimeHHmmByWeekday,
      workingWeekdays: everyDay,
    );
  }
}
