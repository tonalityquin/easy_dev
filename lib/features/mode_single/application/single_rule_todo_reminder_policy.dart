class SingleRuleTodoReminderPolicyResult {
  const SingleRuleTodoReminderPolicyResult({
    required this.shouldShow,
    required this.reason,
    required this.probability,
    required this.roll,
  });

  final bool shouldShow;
  final String reason;
  final double probability;
  final double roll;
}

class SingleRuleTodoReminderPolicy {
  const SingleRuleTodoReminderPolicy();

  static const int cooldownClockIns = 3;
  static const int baseProbabilityUntilMisses = 8;
  static const int guaranteedAttempt = 20;
  static const double baseProbability = 0.06;
  static const double probabilityStep = 0.015;
  static const double maxProbability = 0.18;

  SingleRuleTodoReminderPolicyResult evaluate({
    required int clockInsSinceReminder,
    required int reminderCount,
    required double roll,
  }) {
    final normalizedCount = clockInsSinceReminder < 0 ? 0 : clockInsSinceReminder;
    final normalizedReminderCount = reminderCount < 0 ? 0 : reminderCount;
    final normalizedRoll = roll.clamp(0.0, 1.0).toDouble();

    if (normalizedReminderCount > 0 &&
        normalizedCount < cooldownClockIns) {
      return SingleRuleTodoReminderPolicyResult(
        shouldShow: false,
        reason: 'cooldown',
        probability: 0,
        roll: normalizedRoll,
      );
    }

    if (normalizedCount >= guaranteedAttempt - 1) {
      return SingleRuleTodoReminderPolicyResult(
        shouldShow: true,
        reason: 'guaranteed_threshold',
        probability: 1,
        roll: normalizedRoll,
      );
    }

    final extraMisses = normalizedCount >= baseProbabilityUntilMisses
        ? normalizedCount - baseProbabilityUntilMisses + 1
        : 0;
    final probability = (baseProbability + probabilityStep * extraMisses)
        .clamp(baseProbability, maxProbability)
        .toDouble();
    final shouldShow = normalizedRoll < probability;

    return SingleRuleTodoReminderPolicyResult(
      shouldShow: shouldShow,
      reason: shouldShow ? 'random_hit' : 'random_miss',
      probability: probability,
      roll: normalizedRoll,
    );
  }
}
