import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_attendance_reader.dart';
import 'local_work_schedule_reader.dart';

enum CheckoutOverlayDecisionType {
  none,
  checkoutNudge,
  workFinished,
}

class CheckoutNudgeDecision {
  final CheckoutOverlayDecisionType type;
  final String reason;
  final DateTime? scheduledEnd;

  const CheckoutNudgeDecision({
    required this.type,
    required this.reason,
    this.scheduledEnd,
  });

  bool get shouldNudge => type == CheckoutOverlayDecisionType.checkoutNudge;

  bool get shouldShowWorkFinished =>
      type == CheckoutOverlayDecisionType.workFinished;
}

class CheckoutNudgeGuard {
  CheckoutNudgeGuard._();

  static const Duration grace = Duration.zero;

  static Future<CheckoutNudgeDecision> evaluate({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final isWorking = prefs.getBool('isWorking') ?? false;
    final todayState = await LocalAttendanceReader.instance.readDay(current);

    if (!isWorking) {
      final decision = todayState.hasWorkOut
          ? const CheckoutNudgeDecision(
              type: CheckoutOverlayDecisionType.workFinished,
              reason: 'already_worked_out_today_and_not_working',
            )
          : const CheckoutNudgeDecision(
              type: CheckoutOverlayDecisionType.none,
              reason: 'isWorking=false',
            );
      _logDecision(
        decision: decision,
        isWorking: isWorking,
        hasOpenSession: false,
      );
      return decision;
    }

    final openSessionDate =
        await LocalAttendanceReader.instance.findOpenWorkSessionDate();
    final sessionDate = openSessionDate ?? DateTime(
      current.year,
      current.month,
      current.day,
    );

    final schedule = LocalWorkScheduleReader.readForSessionDate(
      prefs: prefs,
      sessionDate: sessionDate,
    );
    final scheduledEnd = _resolveScheduledEndDateTime(
      sessionDate: sessionDate,
      start: schedule.start,
      end: schedule.end,
    );

    if (scheduledEnd == null) {
      const decision = CheckoutNudgeDecision(
        type: CheckoutOverlayDecisionType.none,
        reason: 'no_scheduled_end_time',
      );
      _logDecision(
        decision: decision,
        isWorking: isWorking,
        hasOpenSession: openSessionDate != null,
      );
      return decision;
    }

    if (current.isBefore(scheduledEnd.add(grace))) {
      final decision = CheckoutNudgeDecision(
        type: CheckoutOverlayDecisionType.none,
        reason: 'before_scheduled_end_time',
        scheduledEnd: scheduledEnd,
      );
      _logDecision(
        decision: decision,
        isWorking: isWorking,
        hasOpenSession: openSessionDate != null,
      );
      return decision;
    }

    final decision = CheckoutNudgeDecision(
      type: CheckoutOverlayDecisionType.checkoutNudge,
      reason: 'after_scheduled_end_time_while_working',
      scheduledEnd: scheduledEnd,
    );
    _logDecision(
      decision: decision,
      isWorking: isWorking,
      hasOpenSession: openSessionDate != null,
    );
    return decision;
  }

  static DateTime? _resolveScheduledEndDateTime({
    required DateTime sessionDate,
    required LocalClockTime? start,
    required LocalClockTime? end,
  }) {
    if (end == null) return null;

    var scheduledEnd = DateTime(
      sessionDate.year,
      sessionDate.month,
      sessionDate.day,
      end.hour,
      end.minute,
    );

    if (start != null) {
      final scheduledStart = DateTime(
        sessionDate.year,
        sessionDate.month,
        sessionDate.day,
        start.hour,
        start.minute,
      );
      if (!scheduledEnd.isAfter(scheduledStart)) {
        scheduledEnd = scheduledEnd.add(const Duration(days: 1));
      }
    }

    return scheduledEnd;
  }

  static void _logDecision({
    required CheckoutNudgeDecision decision,
    required bool isWorking,
    required bool hasOpenSession,
  }) {
    final now = DateTime.now();
    final secondsUntilBoundary = decision.scheduledEnd == null
        ? null
        : decision.scheduledEnd!.difference(now).inSeconds;
    debugPrint(
      '[CheckoutBoundary][local] type=${decision.type.name} reason=${decision.reason} isWorking=$isWorking hasOpenSession=$hasOpenSession hasScheduledEnd=${decision.scheduledEnd != null} secondsUntilBoundary=${secondsUntilBoundary ?? -1}',
    );
  }
}
