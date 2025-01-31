double calculateParkingFee({
  required int entryTimeInMinutes,
  required int currentTimeInMinutes,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
}) {
  // 🚨 예외 처리: 기본 기준 시간이 0이면 기본 요금만 반환
  if (basicStandard <= 0) {
    return basicAmount.toDouble();
  }

  // ✅ 주차 시간 계산
  int totalTime = currentTimeInMinutes - entryTimeInMinutes;

  // ✅ 기본 요금 적용 (최소한 기본 요금 보장)
  if (totalTime <= 0) {
    return basicAmount.toDouble();
  }

  // ✅ 기본 요금 적용
  if (totalTime <= basicStandard) {
    return basicAmount.toDouble();
  }

  // ✅ 추가 요금 계산
  int extraTime = totalTime - basicStandard;
  int extraUnits = addStandard > 0 ? (extraTime / addStandard).ceil() : 0;

  // ✅ 추가 시간이 0 이하일 경우 추가 요금 없음
  if (extraUnits <= 0) {
    return basicAmount.toDouble();
  }

  return (basicAmount + (extraUnits * addAmount)).toDouble(); // 🔹 int → double 변환
}
