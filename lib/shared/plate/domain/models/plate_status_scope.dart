enum PlateStatusScope {
  history,
  monthly,
}

extension PlateStatusScopeLabel on PlateStatusScope {
  String get storageLabel {
    switch (this) {
      case PlateStatusScope.history:
        return 'history';
      case PlateStatusScope.monthly:
        return 'monthly';
    }
  }
}

DateTime? readPlateStatusDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  try {
    final dynamic dynamicValue = value;
    final converted = dynamicValue.toDate();
    if (converted is DateTime) {
      return DateTime(converted.year, converted.month, converted.day);
    }
  } catch (_) {}
  if (value is num) {
    try {
      final milliseconds = value > 100000000000
          ? value.toInt()
          : value.toInt() * 1000;
      final converted = DateTime.fromMillisecondsSinceEpoch(milliseconds);
      return DateTime(converted.year, converted.month, converted.day);
    } catch (_) {
      return null;
    }
  }
  final parsed = DateTime.tryParse(value.toString().trim());
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

bool isMonthlyStatusActive(
  Map<String, dynamic>? data, {
  DateTime? now,
}) {
  if (data == null) return false;
  final explicitActive = data['isActive'];
  if (explicitActive == false) return false;
  final todaySource = now ?? DateTime.now();
  final today = DateTime(
    todaySource.year,
    todaySource.month,
    todaySource.day,
  );
  final startDate = readPlateStatusDate(data['startDate']);
  final endDate = readPlateStatusDate(data['endDate']);
  if (startDate != null && today.isBefore(startDate)) return false;
  if (endDate != null) return !today.isAfter(endDate);
  return explicitActive == true;
}
