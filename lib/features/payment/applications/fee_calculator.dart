enum FeeMode { normal, plus, minus }

int calculateFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
}) {
  final parkedSeconds = currentTimeInSeconds - entryTimeInSeconds;
  final basicSeconds = basicStandard * 60;
  final addSeconds = addStandard * 60;

  if (parkedSeconds <= basicSeconds) {
    return basicAmount;
  }

  final extraSeconds = parkedSeconds - basicSeconds;
  final extraUnits = addSeconds > 0 ? (extraSeconds / addSeconds).ceil() : 0;
  return basicAmount + (extraUnits * addAmount);
}

int applyFeeAdjustment({
  required int baseFee,
  required int userAdjustment,
  required FeeMode mode,
}) {
  switch (mode) {
    case FeeMode.normal:
      return baseFee;
    case FeeMode.plus:
      return baseFee + userAdjustment;
    case FeeMode.minus:
      final discounted = baseFee - userAdjustment;
      return discounted < 0 ? 0 : discounted;
  }
}
