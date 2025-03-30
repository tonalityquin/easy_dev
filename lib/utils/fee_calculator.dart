double calculateParkingFee({
  required int entryTimeInSeconds,   // ⏱ 입장 시각 (초 단위)
  required int currentTimeInSeconds, // ⏱ 현재 시각 (초 단위)
  required int basicStandard,        // ✅ 기본 시간 (분 단위)
  required int basicAmount,          // ✅ 기본 요금
  required int addStandard,          // ✅ 추가 시간 단위 (분 단위)
  required int addAmount,            // ✅ 추가 요금
}) {
  if (basicStandard <= 0) return basicAmount.toDouble();

  int totalSeconds = currentTimeInSeconds - entryTimeInSeconds;
  if (totalSeconds <= 0) return basicAmount.toDouble();

  double totalMinutes = totalSeconds / 60.0;
  if (totalMinutes <= basicStandard) return basicAmount.toDouble();

  if (addStandard <= 0 || addAmount <= 0) return basicAmount.toDouble();

  double extraMinutes = totalMinutes - basicStandard;
  int extraUnits = (extraMinutes / addStandard).ceil();

  return (basicAmount + (extraUnits * addAmount)).toDouble();
}
