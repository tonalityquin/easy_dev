import '../../../domain/monthly_parking_options.dart';

class MonthlySettingsDraft {
  const MonthlySettingsDraft({
    required this.region,
    required this.frontDigit,
    required this.middleDigit,
    required this.backDigit,
    required this.countType,
    required this.regularType,
    required this.regularAmount,
    required this.duration,
    required this.periodUnit,
    required this.startDate,
    required this.endDate,
    required this.customStatus,
    required this.specialNote,
  });

  final String region;
  final String frontDigit;
  final String middleDigit;
  final String backDigit;
  final String countType;
  final String? regularType;
  final int? regularAmount;
  final int? duration;
  final String periodUnit;
  final String startDate;
  final String endDate;
  final String customStatus;
  final String specialNote;

  factory MonthlySettingsDraft.empty() {
    return MonthlySettingsDraft(
      region: '전국',
      frontDigit: '',
      middleDigit: '',
      backDigit: '',
      countType: '',
      regularType: null,
      regularAmount: null,
      duration: null,
      periodUnit: MonthlyParkingOptions.defaultPeriodUnit(
            MonthlyParkingOptions.monthly,
          ) ??
          '월',
      startDate: '',
      endDate: '',
      customStatus: '',
      specialNote: '',
    );
  }

  factory MonthlySettingsDraft.fromRecord({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final plate = docId.split('_').first;
    final parts = plate.split('-');
    final regularType = MonthlyParkingOptions.normalizeRegularType(
      data['regularType']?.toString(),
    );
    return MonthlySettingsDraft(
      region: (data['region'] ?? '전국').toString(),
      frontDigit: parts.length == 3 ? parts[0] : '',
      middleDigit: parts.length == 3 ? parts[1] : '',
      backDigit: parts.length == 3 ? parts[2] : '',
      countType: (data['countType'] ?? '').toString(),
      regularType: regularType,
      regularAmount: _asNullableInt(data['regularAmount']),
      duration: _asNullableInt(
        data['regularDurationValue'] ?? data['regularDurationHours'],
      ),
      periodUnit: MonthlyParkingOptions.resolvePeriodUnit(
        regularType: regularType,
        periodUnit: data['periodUnit']?.toString(),
      ),
      startDate: (data['startDate'] ?? '').toString(),
      endDate: (data['endDate'] ?? '').toString(),
      customStatus: (data['customStatus'] ?? '').toString(),
      specialNote: (data['specialNote'] ?? '').toString(),
    );
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  String get plateNumber => '$frontDigit-$middleDigit-$backDigit';

  MonthlySettingsDraft copyWith({
    String? region,
    String? frontDigit,
    String? middleDigit,
    String? backDigit,
    String? countType,
    String? regularType,
    bool clearRegularType = false,
    int? regularAmount,
    bool clearRegularAmount = false,
    int? duration,
    bool clearDuration = false,
    String? periodUnit,
    String? startDate,
    String? endDate,
    String? customStatus,
    String? specialNote,
  }) {
    return MonthlySettingsDraft(
      region: region ?? this.region,
      frontDigit: frontDigit ?? this.frontDigit,
      middleDigit: middleDigit ?? this.middleDigit,
      backDigit: backDigit ?? this.backDigit,
      countType: countType ?? this.countType,
      regularType:
          clearRegularType ? null : regularType ?? this.regularType,
      regularAmount:
          clearRegularAmount ? null : regularAmount ?? this.regularAmount,
      duration: clearDuration ? null : duration ?? this.duration,
      periodUnit: periodUnit ?? this.periodUnit,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      customStatus: customStatus ?? this.customStatus,
      specialNote: specialNote ?? this.specialNote,
    );
  }

  MonthlySettingsDraft detached() {
    return MonthlySettingsDraft(
      region: region,
      frontDigit: frontDigit,
      middleDigit: middleDigit,
      backDigit: backDigit,
      countType: countType,
      regularType: regularType,
      regularAmount: regularAmount,
      duration: duration,
      periodUnit: periodUnit,
      startDate: startDate,
      endDate: endDate,
      customStatus: customStatus,
      specialNote: specialNote,
    );
  }
}
