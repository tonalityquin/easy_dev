import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final String id;
  final String locationName;
  final String area;
  final bool isSelected;

  // ✅ 복합 주차 구역 관련 필드
  final String? parent; // 상위 구역 이름 (복합일 경우)
  final String? type;   // 'composite' 또는 null

  LocationModel({
    required this.id,
    required this.locationName,
    required this.area,
    required this.isSelected,
    this.parent,
    this.type,
  });

  /// ✅ Firestore 문서에서 모델로 변환
  factory LocationModel.fromMap(String id, Map<String, dynamic> data) {
    return LocationModel(
      id: id,
      locationName: data['locationName'] ?? '',
      area: data['area'] ?? '',
      isSelected: data['isSelected'] ?? false,
      parent: data['parent'],
      type: data['type'],
    );
  }

  /// ✅ Firestore 저장용 Map 변환
  Map<String, dynamic> toFirestoreMap() {
    return {
      'locationName': locationName,
      'area': area,
      'parent': parent ?? area,
      'type': type ?? 'single',
      'isSelected': isSelected,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  /// ✅ SharedPreferences 캐시 저장용 Map 변환
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'locationName': locationName,
      'area': area,
      'parent': parent,
      'type': type,
      'isSelected': isSelected,
    };
  }

  /// ✅ 캐시에서 복원 시 사용
  factory LocationModel.fromCacheMap(Map<String, dynamic> data) {
    return LocationModel(
      id: data['id'] ?? '',
      locationName: data['locationName'] ?? '',
      area: data['area'] ?? '',
      parent: data['parent'],
      type: data['type'],
      isSelected: data['isSelected'] ?? false,
    );
  }
}
