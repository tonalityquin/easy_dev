/// 요금 계산 방식 열거형
enum FeeMode { normal, plus, minus }

/// 통합된 요금 계산 함수 (정기 주차 포함)
int calculateFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard, // 분 단위
  required int basicAmount,
  required int addStandard, // 분 단위
  required int addAmount,
  int userAdjustment = 0,
  FeeMode mode = FeeMode.normal,

  // 정기 주차용 필드 추가
  String? billingType,
  int? regularAmount,
}) {
  final isRegular = billingType != null &&
      (billingType.contains('월 주차') || billingType.contains('정기'));

  // 1. 정기 차량 요금 처리
  if (isRegular) {
    final base = regularAmount ?? 0;

    switch (mode) {
      case FeeMode.normal:
        return base;
      case FeeMode.plus:
        return base + userAdjustment;
      case FeeMode.minus:
        final adjusted = base - userAdjustment;
        return adjusted < 0 ? 0 : adjusted;
    }
  }

  // 2. 일반 요금 계산
  final parkedSeconds = currentTimeInSeconds - entryTimeInSeconds;
  final basicSec = basicStandard * 60;
  final addSec = addStandard * 60;

  int baseFee;
  if (parkedSeconds <= basicSec) {
    baseFee = basicAmount;
  } else {
    final extraTime = parkedSeconds - basicSec;
    final extraUnits = (extraTime / addSec).ceil();
    baseFee = basicAmount + (extraUnits * addAmount);
  }

  // 3. 모드에 따른 조정
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
