import 'package:flutter/foundation.dart';

enum BulkTimeEditorKind {
  attendance,
  breakTime,
}

enum BulkDateScope {
  month,
  selected,
}

@immutable
class BulkWeekdayRule {
  const BulkWeekdayRule({
    required this.enabled,
    required this.clockInMinutes,
    required this.clockOutMinutes,
    required this.breakMinutes,
  });

  final bool enabled;
  final int clockInMinutes;
  final int clockOutMinutes;
  final int breakMinutes;

  BulkWeekdayRule copyWith({
    bool? enabled,
    int? clockInMinutes,
    int? clockOutMinutes,
    int? breakMinutes,
  }) {
    return BulkWeekdayRule(
      enabled: enabled ?? this.enabled,
      clockInMinutes: clockInMinutes ?? this.clockInMinutes,
      clockOutMinutes: clockOutMinutes ?? this.clockOutMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
    );
  }
}

@immutable
class BulkTimeRules {
  const BulkTimeRules(this.byWeekday);

  final Map<int, BulkWeekdayRule> byWeekday;

  factory BulkTimeRules.attendanceDefaults() {
    return BulkTimeRules(
      <int, BulkWeekdayRule>{
        for (var weekday = DateTime.monday;
            weekday <= DateTime.sunday;
            weekday++)
          weekday: BulkWeekdayRule(
            enabled: weekday <= DateTime.friday,
            clockInMinutes: 9 * 60,
            clockOutMinutes: 18 * 60,
            breakMinutes: 12 * 60 + 30,
          ),
      },
    );
  }

  factory BulkTimeRules.breakDefaults() {
    return BulkTimeRules(
      <int, BulkWeekdayRule>{
        for (var weekday = DateTime.monday;
            weekday <= DateTime.sunday;
            weekday++)
          weekday: BulkWeekdayRule(
            enabled: weekday <= DateTime.friday,
            clockInMinutes: 9 * 60,
            clockOutMinutes: 18 * 60,
            breakMinutes: 12 * 60 + 30,
          ),
      },
    );
  }

  BulkWeekdayRule ruleFor(int weekday) {
    return byWeekday[weekday] ??
        const BulkWeekdayRule(
          enabled: false,
          clockInMinutes: 9 * 60,
          clockOutMinutes: 18 * 60,
          breakMinutes: 12 * 60 + 30,
        );
  }

  BulkTimeRules update(int weekday, BulkWeekdayRule rule) {
    return BulkTimeRules(<int, BulkWeekdayRule>{
      ...byWeekday,
      weekday: rule,
    });
  }
}

@immutable
class BulkTimeApplyResult {
  const BulkTimeApplyResult({
    this.clockIns = const <int, String>{},
    this.clockOuts = const <int, String>{},
    this.breakTimes = const <int, String>{},
    this.targetDates = 0,
    this.existingFields = 0,
    this.skippedDates = 0,
  });

  final Map<int, String> clockIns;
  final Map<int, String> clockOuts;
  final Map<int, String> breakTimes;
  final int targetDates;
  final int existingFields;
  final int skippedDates;

  int get generatedFields =>
      clockIns.length + clockOuts.length + breakTimes.length;
}
