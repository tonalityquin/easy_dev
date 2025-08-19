import '../widgets/dialog/billing_bottom_sheet/fee_calculator.dart';

double calculateParkingFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
  bool isLockedFee = false,
  int? lockedAtTimeInSeconds,
  int userAdjustment = 0,
  FeeMode mode = FeeMode.normal,
}) {
  if (basicStandard <= 0) return basicAmount.toDouble();

  final effectiveTime = isLockedFee ? (lockedAtTimeInSeconds ?? currentTimeInSeconds) : currentTimeInSeconds;

  int totalSeconds = effectiveTime - entryTimeInSeconds;
  if (totalSeconds <= 0) return basicAmount.toDouble();

  double totalMinutes = totalSeconds / 60.0;
  if (totalMinutes <= basicStandard) return basicAmount.toDouble();

  if (addStandard <= 0 || addAmount <= 0) return basicAmount.toDouble();

  double extraMinutes = totalMinutes - basicStandard;
  int extraUnits = (extraMinutes / addStandard).ceil();

  double baseFee = basicAmount.toDouble() + (extraUnits * addAmount).toDouble();

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
