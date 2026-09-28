import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account/applications/user_state.dart';
import 'work_schedule_prefs.dart';

class MissingWeekdayEndTimeRequirement {
  const MissingWeekdayEndTimeRequirement({required this.day});

  final String day;
}

Future<MissingWeekdayEndTimeRequirement?>
    resolveMissingWeekdayEndTimeRequirement(
  BuildContext context, {
  DateTime? clockInAt,
}) async {
  if (!context.mounted) return null;

  final userState = context.read<UserState>();
  if (userState.isTablet) return null;

  final target = clockInAt ?? DateTime.now();
  final now = DateTime.now();
  if (!_isSameDate(target, now)) return null;

  final prefs = await SharedPreferences.getInstance();
  final endByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
    prefs,
    WorkSchedulePrefs.endMapKey,
  );
  final day = WorkSchedulePrefs.days[target.weekday - 1];
  if (endByDay[day] != null) return null;

  return MissingWeekdayEndTimeRequirement(day: day);
}

Future<bool> saveMissingWeekdayEndTime(
  BuildContext context, {
  required String day,
  required TimeOfDay endTime,
}) async {
  if (!context.mounted) return false;
  return context.read<UserState>().setCurrentUserWeekdayEndTime(
        day: day,
        endTime: endTime,
      );
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
