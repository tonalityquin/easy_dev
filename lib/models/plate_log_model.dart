import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory PlateLogModel.fromMap(Map<String, dynamic> map) {
    return PlateLogModel(
      plateNumber: map['plateNumber'] ?? '',
      area: map['area'] ?? '',
      from: map['from'] ?? '',
      to: map['to'] ?? '',
      action: map['action'] ?? '',
      performedBy: map['performedBy'] ?? '',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }
}
