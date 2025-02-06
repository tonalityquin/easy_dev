double calculateParkingFee({
  required int entryTimeInMinutes,
  required int currentTimeInMinutes,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
}) {
  if (basicStandard <= 0) {
    return basicAmount.toDouble();
  }

  int totalTime = currentTimeInMinutes - entryTimeInMinutes;
  if (totalTime <= 0) {
    return basicAmount.toDouble();
  }

  if (totalTime <= basicStandard) {
    return basicAmount.toDouble();
  }

  if (addStandard <= 0 || addAmount <= 0) {
    return basicAmount.toDouble();
  }

  int extraUnits = ((totalTime - basicStandard) + (addStandard - 1)) ~/ addStandard; // 🔥 반올림 방식 수정
  return (basicAmount + (extraUnits * addAmount)).toDouble();
}
