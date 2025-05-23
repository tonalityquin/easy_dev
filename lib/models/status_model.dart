class StatusModel {
  final String id;
  final String name;
  final bool isActive;
  final String area;

  StatusModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.area,
  });

  /// ✅ Firestore → 모델
  factory StatusModel.fromMap(String id, Map<String, dynamic> data) {
    return StatusModel(
      id: id,
      name: data['name'] ?? '',
      isActive: data['isActive'] ?? false,
      area: data['area'] ?? '',
    );
  }

  /// ✅ Firestore 저장용
  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name,
      'isActive': isActive,
      'area': area,
    };
  }

  /// ✅ SharedPreferences 저장용
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'area': area,
    };
  }

  /// ✅ 캐시 → 모델
  factory StatusModel.fromCacheMap(Map<String, dynamic> data) {
    return StatusModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      isActive: data['isActive'] ?? false,
      area: data['area'] ?? '',
    );
  }

  @override
  String toString() {
    return 'StatusModel(id: $id, name: $name, isActive: $isActive, area: $area)';
  }
}
