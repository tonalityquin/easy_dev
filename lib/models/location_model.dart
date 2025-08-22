import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final String id;
  final String area;
  final int capacity;
  final bool isSelected;
  final String locationName;
  final String? parent;
  final String? type;
  final int plateCount;

  LocationModel({
    required this.id,
    required this.area,
    required this.capacity,
    required this.isSelected,
    required this.locationName,
    this.parent,
    this.type,
    this.plateCount = 0,
  }) : assert(id.isNotEmpty, 'ID cannot be empty');

  factory LocationModel.create({
    required String area,
    required int capacity,
    required bool isSelected,
    required String locationName,
    String? parent,
    String? type,
  }) {
    final generatedId = '${locationName}_$area';
    return LocationModel(
      id: generatedId,
      area: area,
      capacity: capacity,
      isSelected: isSelected,
      locationName: locationName,
      parent: parent,
      type: type,
    );
  }

  factory LocationModel.fromMap(String id, Map<String, dynamic> data) {
    return LocationModel(
      id: id,
      area: data['area'] ?? '',
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      isSelected: data['isSelected'] ?? false,
      locationName: data['locationName'] ?? '',
      parent: data['parent'],
      type: data['type'],
      plateCount: (data['plateCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final resolvedType = type ?? 'single';
    return {
      'area': area,
      'capacity': capacity,
      'isSelected': isSelected,
      'locationName': locationName,
      'parent': resolvedType == 'single' ? locationName : (parent ?? ''),
      'timestamp': FieldValue.serverTimestamp(),
      'type': resolvedType,
    };
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'area': area,
      'capacity': capacity,
      'isSelected': isSelected,
      'locationName': locationName,
      'parent': parent,
      'type': type,
      'plateCount': plateCount,
    };
  }

  factory LocationModel.fromCacheMap(Map<String, dynamic> data) {
    return LocationModel(
      id: data['id'] ?? '',
      area: data['area'] ?? '',
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      isSelected: data['isSelected'] ?? false,
      locationName: data['locationName'] ?? '',
      parent: data['parent'],
      type: data['type'],
      plateCount: (data['plateCount'] as num?)?.toInt() ?? 0,
    );
  }

  LocationModel copyWith({
    String? id,
    String? area,
    int? capacity,
    bool? isSelected,
    String? locationName,
    String? parent,
    String? type,
    int? plateCount,
  }) {
    return LocationModel(
      id: id ?? this.id,
      area: area ?? this.area,
      capacity: capacity ?? this.capacity,
      isSelected: isSelected ?? this.isSelected,
      locationName: locationName ?? this.locationName,
      parent: parent ?? this.parent,
      type: type ?? this.type,
      plateCount: plateCount ?? this.plateCount,
    );
  }
}
