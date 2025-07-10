import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final String id;
  final String locationName;
  final String area;
  final bool isSelected;
  final int capacity;

  final String? parent; // 상위 구역 이름 (복합일 경우)
  final String? type;   // 'single' | 'composite'

  /// ✅ 입차 수 필드 추가
  final int plateCount;

  LocationModel({
    required this.id,
    required this.locationName,
    required this.area,
    required this.isSelected,
    required this.capacity,
    this.parent,
    this.type,
    this.plateCount = 0, // 기본값
  }) : assert(id.isNotEmpty, 'ID cannot be empty');

  /// ✅ 편의 생성자: ID 자동 생성 (locationName_area 형식)
  factory LocationModel.create({
    required String locationName,
    required String area,
    required bool isSelected,
    required int capacity,
    String? parent,
    String? type,
  }) {
    final generatedId = '${locationName}_$area';
    return LocationModel(
      id: generatedId,
      locationName: locationName,
      area: area,
      isSelected: isSelected,
      capacity: capacity,
      parent: parent,
      type: type,
    );
  }

  /// ✅ Firestore → 모델
  factory LocationModel.fromMap(String id, Map<String, dynamic> data) {
    return LocationModel(
      id: id,
      locationName: data['locationName'] ?? '',
      area: data['area'] ?? '',
      isSelected: data['isSelected'] ?? false,
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      parent: data['parent'],
      type: data['type'],
      plateCount: (data['plateCount'] as num?)?.toInt() ?? 0, // ✅
    );
  }

  /// ✅ 모델 → Firestore Map
  Map<String, dynamic> toFirestoreMap() {
    final resolvedType = type ?? 'single';
    return {
      'locationName': locationName,
      'area': area,
      'parent': resolvedType == 'single' ? locationName : (parent ?? ''),
      'type': resolvedType,
      'isSelected': isSelected,
      'capacity': capacity,
      'timestamp': FieldValue.serverTimestamp(),
      // plateCount는 Firestore에는 저장하지 않음
    };
  }

  /// ✅ 모델 → SharedPreferences 캐시용 Map
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'locationName': locationName,
      'area': area,
      'parent': parent,
      'type': type,
      'isSelected': isSelected,
      'capacity': capacity,
      'plateCount': plateCount, // ✅
    };
  }

  /// ✅ SharedPreferences 캐시 → 모델
  factory LocationModel.fromCacheMap(Map<String, dynamic> data) {
    return LocationModel(
      id: data['id'] ?? '',
      locationName: data['locationName'] ?? '',
      area: data['area'] ?? '',
      isSelected: data['isSelected'] ?? false,
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      parent: data['parent'],
      type: data['type'],
      plateCount: (data['plateCount'] as num?)?.toInt() ?? 0, // ✅
    );
  }

  /// ✅ 복사 및 수정용 copyWith
  LocationModel copyWith({
    String? id,
    String? locationName,
    String? area,
    bool? isSelected,
    String? parent,
    String? type,
    int? capacity,
    int? plateCount, // ✅
  }) {
    return LocationModel(
      id: id ?? this.id,
      locationName: locationName ?? this.locationName,
      area: area ?? this.area,
      isSelected: isSelected ?? this.isSelected,
      parent: parent ?? this.parent,
      type: type ?? this.type,
      capacity: capacity ?? this.capacity,
      plateCount: plateCount ?? this.plateCount,
    );
  }
}
