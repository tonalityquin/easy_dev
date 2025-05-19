import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final String id;
  final String locationName;
  final String area;
  final bool isSelected;

  // ✅ 복합 주차 구역 관련 필드
  final String? parent; // 상위 구역 이름 (복합일 경우)
  final String? type; // 'composite' 또는 null

  LocationModel({
    required this.id,
    required this.locationName,
    required this.area,
    required this.isSelected,
    this.parent,
    this.type,
  });

  /// Firestore 문서에서 모델로 변환
  factory LocationModel.fromMap(String id, Map<String, dynamic> data) {
    return LocationModel(
      id: id,
      locationName: data['locationName'] ?? '',
      area: data['area'] ?? '',
      isSelected: data['isSelected'] ?? false,
      parent: data['parent'],
      // null 가능
      type: data['type'], // null 가능
    );
  }

  /// 모델을 Firestore 저장용 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'locationName': locationName,
      'area': area,
      'parent': parent ?? area, // 🔹 parent가 없으면 area 사용
      'type': type ?? 'single', // 🔹 기본값은 single
      'isSelected': isSelected,
      'timestamp': FieldValue.serverTimestamp(), // 🔹 Firestore 기준 시간
    };
  }
}