import 'package:cloud_firestore/cloud_firestore.dart';

String normalizeSectorName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

String buildSectorDocumentId({
  required String name,
  required String area,
}) {
  return '${name.trim()}_${area.trim()}';
}

class SectorDuplicateNameException implements Exception {
  const SectorDuplicateNameException(this.name);

  final String name;

  @override
  String toString() => '현재 지역에 동일한 섹터명이 이미 존재합니다: $name';
}

class SectorAreaMismatchException implements Exception {
  const SectorAreaMismatchException();

  @override
  String toString() => '현재 지역에 속한 섹터가 아닙니다.';
}

class SectorNotFoundException implements Exception {
  const SectorNotFoundException();

  @override
  String toString() => '섹터 정보를 찾을 수 없습니다.';
}

class SectorModel {
  const SectorModel({
    required this.id,
    required this.area,
    required this.name,
    required this.normalizedName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String area;
  final String name;
  final String normalizedName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SectorModel.fromMap(String id, Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().trim();
    final normalized = (data['normalizedName'] ?? '').toString().trim();
    return SectorModel(
      id: id.trim(),
      area: (data['area'] ?? '').toString().trim(),
      name: name,
      normalizedName: normalizeSectorName(
        normalized.isEmpty ? name : normalized,
      ),
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  factory SectorModel.fromCacheMap(Map<String, dynamic> data) {
    return SectorModel.fromMap(
      (data['id'] ?? '').toString(),
      data,
    );
  }

  SectorModel copyWith({
    String? id,
    String? area,
    String? name,
    String? normalizedName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SectorModel(
      id: id ?? this.id,
      area: area ?? this.area,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toCacheMap() {
    return <String, dynamic>{
      'id': id,
      'area': area,
      'name': name,
      'normalizedName': normalizedName,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }
}
