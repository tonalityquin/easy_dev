class PlateLogModel {
  final String plateNumber;
  final String area;
  final String from;
  final String to;
  final String action;
  final String performedBy;
  final DateTime timestamp;

  PlateLogModel({
    required this.plateNumber,
    required this.area,
    required this.from,
    required this.to,
    required this.action,
    required this.performedBy,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'plateNumber': plateNumber,
    'area': area,
    'from': from,
    'to': to,
    'action': action,
    'performedBy': performedBy,
    'timestamp': timestamp,
  };
}
