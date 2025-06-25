class PlateLogModel {
  final String plateNumber;
  final String division;
  final String area;
  final String from;
  final String to;
  final String action;
  final String performedBy;
  final DateTime timestamp;
  final String? billingType;
  final Map<String, dynamic>? updatedFields; // ✅ 추가

  PlateLogModel({
    required this.plateNumber,
    required this.division,
    required this.area,
    required this.from,
    required this.to,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    this.billingType,
    this.updatedFields,
  });

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'plateNumber': plateNumber,
      'division': division,
      'area': area,
      'from': from,
      'to': to,
      'action': action,
      'performedBy': performedBy,
      'timestamp': timestamp.toIso8601String(),
    };

    final cleanBillingType = billingType?.trim();
    if (cleanBillingType != null && cleanBillingType.isNotEmpty) {
      map['billType'] = cleanBillingType;
    }

    if (updatedFields != null && updatedFields!.isNotEmpty) {
      map['updatedFields'] = updatedFields;
    }

    return map;
  }

  factory PlateLogModel.fromMap(Map<String, dynamic> map) {
    DateTime parsedTime;

    if (map['timestamp'] is String) {
      parsedTime = DateTime.tryParse(map['timestamp']) ?? DateTime.now();
    } else if (map['timestamp'] is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(map['timestamp']);
    } else {
      parsedTime = DateTime.now();
    }

    return PlateLogModel(
      plateNumber: map['plateNumber'] ?? '',
      division: map['division'] ?? '',
      area: map['area'] ?? '',
      from: map['from'] ?? '',
      to: map['to'] ?? '',
      action: map['action'] ?? '',
      performedBy: map['performedBy'] ?? '',
      timestamp: parsedTime,
      billingType: map['billType'] as String?,
      updatedFields: map['updatedFields'] is Map
          ? Map<String, dynamic>.from(
              (map['updatedFields'] as Map).map(
                (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
              ),
            )
          : null,
    );
  }
}
