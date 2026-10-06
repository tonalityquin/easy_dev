import 'dart:math' as math;

import 'bulk_time_models.dart';

class BulkTimeGenerator {
  const BulkTimeGenerator._();

  static const int spreadMinutes = 10;

  static int daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  static String formatMinutes(int minutes) {
    final normalized = minutes.clamp(0, 1439).toInt();
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static BulkTimeApplyResult generate({
    required BulkTimeEditorKind kind,
    required DateTime month,
    required String userSeed,
    required BulkTimeRules rules,
    required Set<int> targetDays,
    required Map<int, String> currentClockIns,
    required Map<int, String> currentClockOuts,
    required Map<int, String> currentBreakTimes,
    required Map<int, String> loadedClockIns,
    required Map<int, String> loadedClockOuts,
    required Map<int, String> loadedBreakTimes,
    required Set<int> pendingDeleteClockInDays,
    required Set<int> pendingDeleteClockOutDays,
    required Set<int> pendingDeleteBreakDays,
  }) {
    final sortedDays = targetDays.toList()..sort();
    final clockIns = <int, String>{};
    final clockOuts = <int, String>{};
    final breakTimes = <int, String>{};
    var existingFields = 0;
    var skippedDates = 0;

    for (final day in sortedDays) {
      final date = DateTime(month.year, month.month, day);
      final rule = rules.ruleFor(date.weekday);
      if (!rule.enabled) {
        skippedDates++;
        continue;
      }

      if (kind == BulkTimeEditorKind.attendance) {
        final pair = _attendancePair(
          month: month,
          userSeed: userSeed,
          day: day,
          rule: rule,
        );
        final currentInValue = currentClockIns[day] ?? '';
        final loadedInValue = loadedClockIns[day] ?? '';
        final currentOutValue = currentClockOuts[day] ?? '';
        final loadedOutValue = loadedClockOuts[day] ?? '';
        final clockInBlocked = currentInValue.isNotEmpty ||
            loadedInValue.isNotEmpty ||
            pendingDeleteClockInDays.contains(day);
        final clockOutBlocked = currentOutValue.isNotEmpty ||
            loadedOutValue.isNotEmpty ||
            pendingDeleteClockOutDays.contains(day);
        final existingClockIn = _parseMinutes(
          currentInValue.isNotEmpty ? currentInValue : loadedInValue,
        );
        final existingClockOut = _parseMinutes(
          currentOutValue.isNotEmpty ? currentOutValue : loadedOutValue,
        );
        var conflict = false;

        if (clockInBlocked) {
          existingFields++;
        } else {
          var generatedClockIn = pair.clockIn;
          if (existingClockOut != null && generatedClockIn >= existingClockOut) {
            final inMin = _safeMinute(rule.clockInMinutes - spreadMinutes);
            final inMax = _safeMinute(rule.clockInMinutes + spreadMinutes);
            final adjusted = math.min(inMax, existingClockOut - 1).toInt();
            if (adjusted >= inMin && adjusted < existingClockOut) {
              generatedClockIn = adjusted;
            } else {
              conflict = true;
            }
          }
          if (!conflict) {
            clockIns[day] = formatMinutes(generatedClockIn);
          }
        }

        if (clockOutBlocked) {
          existingFields++;
        } else {
          var generatedClockOut = pair.clockOut;
          if (existingClockIn != null && generatedClockOut <= existingClockIn) {
            final outMin = _safeMinute(rule.clockOutMinutes - spreadMinutes);
            final outMax = _safeMinute(rule.clockOutMinutes + spreadMinutes);
            final adjusted = math.max(outMin, existingClockIn + 1).toInt();
            if (adjusted <= outMax && adjusted > existingClockIn) {
              generatedClockOut = adjusted;
            } else {
              conflict = true;
            }
          }
          if (!conflict) {
            clockOuts[day] = formatMinutes(generatedClockOut);
          }
        }

        if (conflict) {
          clockIns.remove(day);
          clockOuts.remove(day);
          skippedDates++;
        }
      } else {
        final blocked = (currentBreakTimes[day] ?? '').isNotEmpty ||
            (loadedBreakTimes[day] ?? '').isNotEmpty ||
            pendingDeleteBreakDays.contains(day);
        if (blocked) {
          existingFields++;
        } else {
          final minutes = _safeMinute(
            rule.breakMinutes +
                _offsetFor(
                  userSeed: userSeed,
                  month: month,
                  day: day,
                  field: 'break',
                ),
          );
          breakTimes[day] = formatMinutes(minutes);
        }
      }
    }

    return BulkTimeApplyResult(
      clockIns: clockIns,
      clockOuts: clockOuts,
      breakTimes: breakTimes,
      targetDates: sortedDays.length,
      existingFields: existingFields,
      skippedDates: skippedDates,
    );
  }

  static _AttendancePair _attendancePair({
    required DateTime month,
    required String userSeed,
    required int day,
    required BulkWeekdayRule rule,
  }) {
    final inMin = _safeMinute(rule.clockInMinutes - spreadMinutes);
    final inMax = _safeMinute(rule.clockInMinutes + spreadMinutes);
    final outMin = _safeMinute(rule.clockOutMinutes - spreadMinutes);
    final outMax = _safeMinute(rule.clockOutMinutes + spreadMinutes);
    var clockIn = _safeMinute(
      rule.clockInMinutes +
          _offsetFor(
            userSeed: userSeed,
            month: month,
            day: day,
            field: 'clockIn',
          ),
    );
    var clockOut = _safeMinute(
      rule.clockOutMinutes +
          _offsetFor(
            userSeed: userSeed,
            month: month,
            day: day,
            field: 'clockOut',
          ),
    );
    clockIn = clockIn.clamp(inMin, inMax).toInt();
    clockOut = clockOut.clamp(outMin, outMax).toInt();
    if (clockOut <= clockIn) {
      clockOut =
          math.min(outMax, math.max(outMin, clockIn + 1)).toInt();
    }
    if (clockOut <= clockIn) {
      clockIn =
          math.max(inMin, math.min(inMax, clockOut - 1)).toInt();
    }
    return _AttendancePair(clockIn: clockIn, clockOut: clockOut);
  }

  static int _offsetFor({
    required String userSeed,
    required DateTime month,
    required int day,
    required String field,
  }) {
    final date =
        '${month.year}-${month.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final hash = _stableHash('$userSeed|$date|$field');
    return hash % (spreadMinutes * 2 + 1) - spreadMinutes;
  }

  static int _stableHash(String input) {
    var hash = 2166136261;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static int? _parseMinutes(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static int _safeMinute(int value) {
    return value.clamp(1, 1439).toInt();
  }
}

class _AttendancePair {
  const _AttendancePair({required this.clockIn, required this.clockOut});

  final int clockIn;
  final int clockOut;
}
