/// 요금 계산 방식 열거형
enum FeeMode { normal, plus, minus }

/// 통합된 요금 계산 함수
int calculateFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard, // 분 단위
  required int basicAmount,
  required int addStandard, // 분 단위
  required int addAmount,
  int userAdjustment = 0, // 추가 또는 할인 금액
  FeeMode mode = FeeMode.normal,
}) {
  // 1. 기본 요금 계산
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

  // 2. 모드에 따른 요금 조정
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
