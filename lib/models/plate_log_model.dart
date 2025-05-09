class PlateLogModel {
  final String plateNumber;
  final String division; // ✅ 추가
  final String area;
  final String from;
  final String to;
  final String action;
  final String performedBy;
  final DateTime timestamp;

  PlateLogModel({
    required this.plateNumber,
    required this.division, // ✅ 추가
    required this.area,
    required this.from,
    required this.to,
    required this.action,
    required this.performedBy,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'plateNumber': plateNumber,
    'division': division, // ✅ 추가
    'area': area,
    'from': from,
    'to': to,
    'action': action,
    'performedBy': performedBy,
    'timestamp': timestamp.toIso8601String(),
  };

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
      division: map['division'] ?? '', // ✅ 추가
      area: map['area'] ?? '',
      from: map['from'] ?? '',
      to: map['to'] ?? '',
      action: map['action'] ?? '',
      performedBy: map['performedBy'] ?? '',
      timestamp: parsedTime,
    );
  }
}
