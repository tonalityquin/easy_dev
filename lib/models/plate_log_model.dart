class PlateLogModel {
  final String plateNumber;
  final String division;
  final String area;
  final String from;
  final String to;
  final String action;
  final String performedBy;
  final DateTime timestamp;
  final String? adjustmentType; // nullable 타입

  PlateLogModel({
    required this.plateNumber,
    required this.division,
    required this.area,
    required this.from,
    required this.to,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    this.adjustmentType,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'plateNumber': plateNumber,
      'division': division,
      'area': area,
      'from': from,
      'to': to,
      'action': action,
      'performedBy': performedBy,
      'timestamp': timestamp.toIso8601String(),
    };

    // ✅ null 또는 공백인 경우 adjustmentType 제외
    final cleanAdjustmentType = adjustmentType?.trim();
    if (cleanAdjustmentType != null && cleanAdjustmentType.isNotEmpty) {
      map['adjustmentType'] = cleanAdjustmentType;
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
      adjustmentType: map['adjustmentType'] as String?, // ✅ 안전한 캐스팅
    );
  }
}
