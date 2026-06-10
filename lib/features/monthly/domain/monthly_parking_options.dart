class MonthlyParkingOptions {
  const MonthlyParkingOptions._();

  static const String monthly = '월 주차';
  static const String daytime = '주간권';
  static const String nighttime = '야간권';
  static const String weekend = '주말권';

  static const List<String> regularTypes = [
    monthly,
    daytime,
    nighttime,
    weekend,
  ];

  static const Map<String, String> defaultPeriodUnitByType = {
    monthly: '월',
    daytime: '주',
    nighttime: '월',
    weekend: '주',
  };

  static String? normalizeRegularType(String? regularType) {
    final value = regularType?.trim();
    if (value == null || value.isEmpty) return null;
    return regularTypes.contains(value) ? value : null;
  }

  static String? defaultPeriodUnit(String? regularType) {
    return defaultPeriodUnitByType[normalizeRegularType(regularType)];
  }

  static bool isWeekendType(String? regularType) {
    return normalizeRegularType(regularType) == weekend;
  }

  static bool isAllowedRegularType(String? value) {
    return normalizeRegularType(value) != null;
  }

  static bool isAllowedPeriodUnit({
    required String? regularType,
    required String? periodUnit,
  }) {
    final expected = defaultPeriodUnit(regularType);
    if (expected == null) return false;
    return periodUnit?.trim() == expected;
  }

  static String resolvePeriodUnit({
    required String? regularType,
    required String? periodUnit,
  }) {
    final expected = defaultPeriodUnit(regularType);
    if (expected != null) return expected;
    final trimmed = periodUnit?.trim();
    if (trimmed == '일' || trimmed == '주' || trimmed == '월') return trimmed!;
    return '월';
  }

  static String durationLabel({
    required String? regularType,
    required int duration,
    required String periodUnit,
  }) {
    final safeDuration = duration <= 0 ? 1 : duration;
    if (isWeekendType(regularType)) return '주말 $safeDuration회';
    return '$safeDuration$periodUnit';
  }
}
