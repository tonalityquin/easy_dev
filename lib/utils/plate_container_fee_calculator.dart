/// ⏱ 통합 주차 요금 계산 함수
double calculateParkingFee({
  required int entryTimeInSeconds,   // 입장 시각 (초 단위)
  required int currentTimeInSeconds, // 현재 시각 (초 단위)
  required int basicStandard,        // 기본 시간 (분 단위)
  required int basicAmount,          // 기본 요금
  required int addStandard,          // 추가 시간 단위 (분 단위)
  required int addAmount,            // 추가 요금
  bool isLockedFee = false,          // ✅ 요금 고정 여부
  int? lockedAtTimeInSeconds,        // ✅ 고정된 시간 (초 단위)
}) {
  if (basicStandard <= 0) return basicAmount.toDouble();

  final effectiveTime = isLockedFee
      ? (lockedAtTimeInSeconds ?? currentTimeInSeconds)
      : currentTimeInSeconds;

  int totalSeconds = effectiveTime - entryTimeInSeconds;
  if (totalSeconds <= 0) return basicAmount.toDouble();

  double totalMinutes = totalSeconds / 60.0;
  if (totalMinutes <= basicStandard) return basicAmount.toDouble();

  if (addStandard <= 0 || addAmount <= 0) return basicAmount.toDouble();

  double extraMinutes = totalMinutes - basicStandard;
  int extraUnits = (extraMinutes / addStandard).ceil();

  return (basicAmount + (extraUnits * addAmount)).toDouble();
}
