class SingleRuleTodoPromptPolicyResult {
  const SingleRuleTodoPromptPolicyResult({
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

class SingleRuleTodoPromptPolicy {
  const SingleRuleTodoPromptPolicy();

  static const int cooldownClockIns = 3;
  static const int baseProbabilityUntilMisses = 8;
  static const int guaranteedAttempt = 20;
  static const double baseProbability = 0.06;
  static const double probabilityStep = 0.015;
  static const double maxProbability = 0.18;

  SingleRuleTodoPromptPolicyResult evaluate({
    required int clockInsSincePrompt,
    required int promptCount,
    required double roll,
  }) {
    final normalizedCount = clockInsSincePrompt < 0 ? 0 : clockInsSincePrompt;
    final normalizedPromptCount = promptCount < 0 ? 0 : promptCount;
    final normalizedRoll = roll.clamp(0.0, 1.0).toDouble();

    if (normalizedPromptCount > 0 &&
        normalizedCount < cooldownClockIns) {
      return SingleRuleTodoPromptPolicyResult(
        shouldShow: false,
        reason: 'cooldown',
        probability: 0,
        roll: normalizedRoll,
      );
    }

    if (normalizedCount >= guaranteedAttempt - 1) {
      return SingleRuleTodoPromptPolicyResult(
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

    return SingleRuleTodoPromptPolicyResult(
      shouldShow: shouldShow,
      reason: shouldShow ? 'random_hit' : 'random_miss',
      probability: probability,
      roll: normalizedRoll,
    );
  }
}
