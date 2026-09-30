import '../models/plate_model.dart';

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

class PlateBillingPlanResolution {
  const PlateBillingPlanResolution({
    required this.regular,
    required this.planType,
    required this.source,
  });

  final bool regular;
  final String planType;
  final String source;
}

PlateBillingPlanResolution resolvePlateBillingPlan(PlateModel plate) {
  final explicitPlan = (plate.billingPlanType ?? '').trim();
  if (explicitPlan.isNotEmpty) {
    final regular = explicitPlan == '정기';
    return PlateBillingPlanResolution(
      regular: regular,
      planType: regular ? '정기' : '변동',
      source: 'billingPlanType',
    );
  }

  if ((plate.regularAmount ?? 0) > 0) {
    return const PlateBillingPlanResolution(
      regular: true,
      planType: '정기',
      source: 'legacy_regularAmount',
    );
  }

  final countType = (plate.billingType ?? '').trim();
  if (countType.contains('정기')) {
    return const PlateBillingPlanResolution(
      regular: true,
      planType: '정기',
      source: 'legacy_billingType_text',
    );
  }

  return const PlateBillingPlanResolution(
    regular: false,
    planType: '변동',
    source: 'legacy_general_fallback',
  );
}

class PlateBillingSnapshotQuote {
  const PlateBillingSnapshotQuote({
    required this.applicable,
    required this.regular,
    required this.planType,
    required this.countType,
    required this.amount,
    required this.snapshotAt,
    required this.source,
  });

  final bool applicable;
  final bool regular;
  final String planType;
  final String countType;
  final int amount;
  final DateTime snapshotAt;
  final String source;

  String get typeLabel {
    if (!applicable) return '';
    final plan = planType.trim();
    final count = countType.trim();
    if (count.isEmpty || count == plan) return plan;
    return '$plan · $count';
  }
}

PlateBillingSnapshotQuote calculatePlateBillingSnapshotQuote({
  required PlateModel plate,
  required DateTime snapshotAt,
}) {
  final explicitPlan = (plate.billingPlanType ?? '').trim();
  final countType = (plate.billingType ?? '').trim();
  final regularAmount = plate.regularAmount ?? 0;
  final hasBilling =
      explicitPlan.isNotEmpty || countType.isNotEmpty || regularAmount > 0;
  if (!hasBilling) {
    return PlateBillingSnapshotQuote(
      applicable: false,
      regular: false,
      planType: '',
      countType: '',
      amount: 0,
      snapshotAt: snapshotAt,
      source: 'none',
    );
  }

  final plan = resolvePlateBillingPlan(plate);
  final amount = plan.regular
      ? regularAmount
      : calculateFee(
          entryTimeInSeconds:
              plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000,
          currentTimeInSeconds:
              snapshotAt.toUtc().millisecondsSinceEpoch ~/ 1000,
          basicStandard: plate.basicStandard ?? 0,
          basicAmount: plate.basicAmount ?? 0,
          addStandard: plate.addStandard ?? 0,
          addAmount: plate.addAmount ?? 0,
        );

  return PlateBillingSnapshotQuote(
    applicable: true,
    regular: plan.regular,
    planType: plan.planType,
    countType: countType,
    amount: amount,
    snapshotAt: snapshotAt,
    source: plan.source,
  );
}
