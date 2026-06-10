DateTime? _readDateTime(dynamic value) {
  if (value == null) return null;

  if (value is DateTime) return value;

  try {
    final dynamic dynamicValue = value;
    final converted = dynamicValue.toDate();
    if (converted is DateTime) return converted;
  } catch (_) {}

  if (value is int) {
    try {
      if (value > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    } catch (_) {
      return null;
    }
  }

  if (value is String) {
    return DateTime.tryParse(value.trim());
  }

  if (value is Map) {
    final seconds = _readInt(value['seconds']);
    final nanoseconds = _readInt(value['nanoseconds']) ?? 0;
    if (seconds != null) {
      final ms = (seconds * 1000) + (nanoseconds ~/ 1000000);
      try {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      } catch (_) {
        return null;
      }
    }
  }

  return null;
}

String? _readTrimmedString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _readRawDateText(dynamic value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int? _readInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<String> _readStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value.map((e) => e.toString()).toList(growable: false);
}

class PlateStatusPaymentRecord {
  final String? amountText;
  final String? paymentAmountText;
  final String? extendedText;
  final String? note;
  final DateTime? paidAt;
  final String? paidAtRaw;
  final String? paidBy;
  final String? regularType;
  final String? periodUnit;
  final int? durationValue;
  final int? regularDurationValue;
  final String? startDate;
  final String? endDate;

  const PlateStatusPaymentRecord({
    required this.amountText,
    required this.paymentAmountText,
    required this.extendedText,
    required this.note,
    required this.paidAt,
    required this.paidAtRaw,
    required this.paidBy,
    required this.regularType,
    required this.periodUnit,
    required this.durationValue,
    required this.regularDurationValue,
    required this.startDate,
    required this.endDate,
  });

  factory PlateStatusPaymentRecord.fromMap(Map<String, dynamic> data) {
    final rawPaidAt = data['paidAt'];
    final paymentAmount = _readTrimmedString(data['paymentAmount']);
    final legacyAmount = _readTrimmedString(data['amount']);
    final duration = _readInt(data['durationValue']) ?? _readInt(data['regularDurationValue']);
    return PlateStatusPaymentRecord(
      amountText: paymentAmount ?? legacyAmount,
      paymentAmountText: paymentAmount,
      extendedText: _readTrimmedString(data['extended']),
      note: _readTrimmedString(data['note']),
      paidAt: _readDateTime(rawPaidAt),
      paidAtRaw: _readRawDateText(rawPaidAt),
      paidBy: _readTrimmedString(data['paidBy']),
      regularType: _readTrimmedString(data['regularType']),
      periodUnit: _readTrimmedString(data['periodUnit']),
      durationValue: duration,
      regularDurationValue: _readInt(data['regularDurationValue']) ?? duration,
      startDate: _readTrimmedString(data['startDate']),
      endDate: _readTrimmedString(data['endDate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amountText,
      'paymentAmount': paymentAmountText ?? amountText,
      'extended': extendedText,
      'note': note,
      'paidAt': paidAtRaw ?? paidAt?.toIso8601String(),
      'paidBy': paidBy,
      'regularType': regularType,
      'periodUnit': periodUnit,
      'durationValue': durationValue,
      'regularDurationValue': regularDurationValue ?? durationValue,
      'startDate': startDate,
      'endDate': endDate,
    };
  }
}

class PlateStatusRecord {
  final String? docId;
  final String? area;
  final String? region;
  final String? specialNote;
  final String? customStatus;
  final DateTime? updatedAt;
  final String? updatedAtRaw;
  final List<String> statusList;
  final String? countType;
  final String? type;
  final String? periodUnit;
  final String? regularType;
  final String? startDate;
  final String? endDate;
  final int? regularAmount;
  final int? regularDurationHours;
  final int? regularDurationValue;
  final List<PlateStatusPaymentRecord> paymentHistory;

  const PlateStatusRecord({
    required this.docId,
    required this.area,
    required this.region,
    required this.specialNote,
    required this.customStatus,
    required this.updatedAt,
    required this.updatedAtRaw,
    required this.statusList,
    required this.countType,
    required this.type,
    required this.periodUnit,
    required this.regularType,
    required this.startDate,
    required this.endDate,
    required this.regularAmount,
    required this.regularDurationHours,
    required this.regularDurationValue,
    required this.paymentHistory,
  });

  factory PlateStatusRecord.fromMap(Map<String, dynamic> data, {String? docId}) {
    final rawUpdatedAt = data['updatedAt'];
    final paymentHistoryRaw = data['payment_history'];
    final durationValue = _readInt(data['regularDurationValue']) ?? _readInt(data['regularDurationHours']);

    return PlateStatusRecord(
      docId: docId,
      area: _readTrimmedString(data['area']),
      region: _readTrimmedString(data['region']),
      specialNote: _readTrimmedString(data['specialNote']),
      customStatus: _readTrimmedString(data['customStatus']),
      updatedAt: _readDateTime(rawUpdatedAt),
      updatedAtRaw: _readRawDateText(rawUpdatedAt),
      statusList: _readStringList(data['statusList']),
      countType: _readTrimmedString(data['countType']),
      type: _readTrimmedString(data['type']),
      periodUnit: _readTrimmedString(data['periodUnit']),
      regularType: _readTrimmedString(data['regularType']),
      startDate: _readTrimmedString(data['startDate']),
      endDate: _readTrimmedString(data['endDate']),
      regularAmount: _readInt(data['regularAmount']),
      regularDurationHours: _readInt(data['regularDurationHours']) ?? durationValue,
      regularDurationValue: durationValue,
      paymentHistory: paymentHistoryRaw is List
          ? paymentHistoryRaw
                .whereType<Map>()
                .map((e) => PlateStatusPaymentRecord.fromMap(
                      Map<String, dynamic>.from(e),
                    ))
                .toList(growable: false)
          : const <PlateStatusPaymentRecord>[],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'area': area,
      'region': region,
      'specialNote': specialNote,
      'customStatus': customStatus,
      'statusList': statusList,
      'type': type,
      'countType': countType,
      'regularType': regularType,
      'regularAmount': regularAmount,
      'regularDurationValue': regularDurationValue ?? regularDurationHours,
      'regularDurationHours': regularDurationHours ?? regularDurationValue,
      'periodUnit': periodUnit,
      'startDate': startDate,
      'endDate': endDate,
      'payment_history': paymentHistory.map((e) => e.toMap()).toList(growable: false),
    };
  }
}

class PlateStatusRepositoryException implements Exception {
  final String message;
  final Object? cause;

  const PlateStatusRepositoryException(this.message, {this.cause});

  @override
  String toString() => message;
}

class PlateStatusReadException extends PlateStatusRepositoryException {
  const PlateStatusReadException(super.message, {super.cause});
}

class MonthlyPlateStatusReadException extends PlateStatusRepositoryException {
  const MonthlyPlateStatusReadException(super.message, {super.cause});
}

class MonthlyPlateStatusWriteException extends PlateStatusRepositoryException {
  const MonthlyPlateStatusWriteException(super.message, {super.cause});
}
