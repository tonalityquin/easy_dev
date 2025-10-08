// ==============================
// File: offline_location_model.dart
// ==============================
import 'package:flutter/foundation.dart';

@immutable
class OfflineLocation {
  final int? id;
  final String locationKey;     // location_name + '_' + area
  final String area;
  final String locationName;
  final String? parent;         // DB에는 ''로 저장됨 (NOT NULL DEFAULT '')
  final String type;            // 'single' | 'composite' 등
  final int capacity;           // 수용대수
  final bool isSelected;
  final String? timestampRaw;   // 입력 원문 문자열 (예: "2025년 10월 7일 ... UTC+9")
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const OfflineLocation({
    this.id,
    required this.locationKey,
    required this.area,
    required this.locationName,
    this.parent,
    required this.type,
    this.capacity = 0,
    this.isSelected = false,
    this.timestampRaw,
    this.updatedAt,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'location_key': locationKey,
    'area': area,
    'location_name': locationName,
    'parent': parent ?? '', // ⬅️ DB 제약 대응: null이면 ''로 저장
    'type': type,
    'capacity': capacity,
    'is_selected': isSelected ? 1 : 0,
    'timestamp_raw': timestampRaw,
    'updated_at': updatedAt?.millisecondsSinceEpoch,
    'created_at': createdAt?.millisecondsSinceEpoch,
  }..removeWhere((k, v) => v == null);

  factory OfflineLocation.fromMap(Map<String, Object?> map) {
    final rawParent = map['parent'] as String?;
    return OfflineLocation(
      id: map['id'] as int?,
      locationKey: (map['location_key'] ?? '') as String,
      area: (map['area'] ?? '') as String,
      locationName: (map['location_name'] ?? '') as String,
      parent: (rawParent == null || rawParent.isEmpty) ? null : rawParent, // ⬅️ ''를 다시 null로 복원
      type: (map['type'] ?? '') as String,
      capacity: (map['capacity'] as int?) ?? 0,
      isSelected: ((map['is_selected'] as int?) ?? 0) == 1,
      timestampRaw: map['timestamp_raw'] as String?,
      updatedAt: (map['updated_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      createdAt: (map['created_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : null,
    );
  }

  static String makeLocationKey({required String locationName, required String area}) =>
      '${locationName}_${area}';
}
