import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/mode_single/application/att_brk_repository.dart';
import 'work_schedule_prefs.dart';

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
    final isWorking = prefs.getBool('isWorking') ?? false;
    final events = await AttBrkRepository.instance.getEventsForDate(current);

    if (!isWorking) {
      if (events.containsKey(AttBrkModeType.workOut)) {
        return const CheckoutNudgeDecision(
          type: CheckoutOverlayDecisionType.workFinished,
          reason: 'already_worked_out_today_and_not_working',
        );
      }

      return const CheckoutNudgeDecision(
        type: CheckoutOverlayDecisionType.none,
        reason: 'isWorking=false',
      );
    }

    final scheduledEnd = _resolveScheduledEndDateTime(
      prefs: prefs,
      now: current,
    );

    if (scheduledEnd == null) {
      return const CheckoutNudgeDecision(
        type: CheckoutOverlayDecisionType.none,
        reason: 'no_scheduled_end_time',
      );
    }

    if (current.isBefore(scheduledEnd.add(grace))) {
      return CheckoutNudgeDecision(
        type: CheckoutOverlayDecisionType.none,
        reason: 'before_scheduled_end_time',
        scheduledEnd: scheduledEnd,
      );
    }

    return CheckoutNudgeDecision(
      type: CheckoutOverlayDecisionType.checkoutNudge,
      reason: 'after_scheduled_end_time_while_working',
      scheduledEnd: scheduledEnd,
    );
  }

  static DateTime? _resolveScheduledEndDateTime({
    required SharedPreferences prefs,
    required DateTime now,
  }) {
    final startByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
      prefs,
      WorkSchedulePrefs.startMapKey,
    );
    final endByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
      prefs,
      WorkSchedulePrefs.endMapKey,
    );
    final hasWeeklyEnd = endByDay.values.any((value) => value != null);

    if (hasWeeklyEnd) {
      return _resolveTodayScheduledEnd(
        startByDay: startByDay,
        endByDay: endByDay,
        now: now,
      );
    }

    final legacyEnd = WorkSchedulePrefs.parseHHmm(
      prefs.getString('endTime'),
    );

    if (legacyEnd == null) return null;

    return DateTime(
      now.year,
      now.month,
      now.day,
      legacyEnd.hour,
      legacyEnd.minute,
    );
  }

  static DateTime? _resolveTodayScheduledEnd({
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
    required DateTime now,
  }) {
    final todayLabel = WorkSchedulePrefs.days[now.weekday - 1];
    final start = startByDay[todayLabel];
    final end = endByDay[todayLabel];

    if (end == null) return null;

    var scheduledEnd = DateTime(
      now.year,
      now.month,
      now.day,
      end.hour,
      end.minute,
    );

    if (start != null) {
      final scheduledStart = DateTime(
        now.year,
        now.month,
        now.day,
        start.hour,
        start.minute,
      );

      if (!scheduledEnd.isAfter(scheduledStart)) {
        scheduledEnd = scheduledEnd.add(const Duration(days: 1));
      }
    }

    return scheduledEnd;
  }
}
