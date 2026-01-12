class NormalParkingCompletedRecord {
  final int? id;
  final String plateNumber; // 전체 번호판
  final String location; // 주차 구역
  final DateTime? createdAt;

  /// 출차 완료 여부 (로컬 전용 플래그)
  final bool isDepartureCompleted;

  const NormalParkingCompletedRecord({
    this.id,
    required this.plateNumber,
    required this.location,
    this.createdAt,
    this.isDepartureCompleted = false,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'plate_number': plateNumber,
      'location': location,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'is_departure_completed': isDepartureCompleted ? 1 : 0,
    }..removeWhere((k, v) => v == null);
  }

  factory NormalParkingCompletedRecord.fromMap(Map<String, Object?> map) {
    return NormalParkingCompletedRecord(
      id: map['id'] as int?,
      plateNumber: (map['plate_number'] ?? '') as String,
      location: (map['location'] ?? '') as String,
      createdAt:
          (map['created_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int) : null,
      isDepartureCompleted: ((map['is_departure_completed'] as int?) ?? 0) == 1,
    );
  }
}
