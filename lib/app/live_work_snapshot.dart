import '../features/mode_single/application/att_brk_repository.dart';

class LiveWorkSnapshot {
  const LiveWorkSnapshot({
    required this.now,
    required this.isWorking,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.breakEnabledToday,
    required this.actualClockIn,
    required this.actualBreak,
    required this.actualClockOut,
  });

  final DateTime now;
  final bool isWorking;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final bool breakEnabledToday;
  final String? actualClockIn;
  final String? actualBreak;
  final String? actualClockOut;

  bool get canPunchBreak =>
      isWorking &&
      breakEnabledToday &&
      actualClockIn != null &&
      actualBreak == null &&
      actualClockOut == null;

  bool get breakCompleted => actualBreak != null;

  String? get currentSessionBreak {
    final clockIn = _minutesOfDay(actualClockIn);
    final breakTime = _minutesOfDay(actualBreak);
    if (actualBreak == null) return null;
    if (clockIn == null || breakTime == null) return actualBreak;
    return breakTime >= clockIn ? actualBreak : null;
  }

  bool get hasStaleBreakForCurrentSession =>
      actualBreak != null && currentSessionBreak == null;

  bool get scheduledEndPassed =>
      scheduledEnd != null && !now.isBefore(scheduledEnd!);

  bool get isOverdue => isWorking && scheduledEndPassed;

  Duration get overdueDuration {
    if (!isOverdue || scheduledEnd == null) return Duration.zero;
    return now.difference(scheduledEnd!);
  }

  int get overdueMinutes => overdueDuration.inMinutes;

  static int? _minutesOfDay(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static String? eventTime(
    Map<AttBrkModeType, String> events,
    AttBrkModeType type,
  ) =>
      events[type];
}
