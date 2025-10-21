import 'package:flutter/foundation.dart';

@immutable
class ParkingCompletedRecord {
  final int? id;
  final String plateNumber; // 전체 번호판
  final String area;        // 주차 구역
  final DateTime? createdAt;

  const ParkingCompletedRecord({
    this.id,
    required this.plateNumber,
    required this.area,
    this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'plate_number': plateNumber,
      'area': area,
      'created_at': createdAt?.millisecondsSinceEpoch,
    }..removeWhere((k, v) => v == null);
  }

  factory ParkingCompletedRecord.fromMap(Map<String, Object?> map) {
    return ParkingCompletedRecord(
      id: map['id'] as int?,
      plateNumber: (map['plate_number'] ?? '') as String,
      area: (map['area'] ?? '') as String,
      createdAt: (map['created_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : null,
    );
  }
}
