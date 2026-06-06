import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class PersonalSavedVehicle {
  const PersonalSavedVehicle({
    required this.id,
    required this.plateNumber,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  final String id;
  final String plateNumber;
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  String get displayLabel => label.trim().isEmpty ? '내 차량' : label.trim();
  String get compactPlate => normalizePersonalPlateNumber(plateNumber);
  String get displayPlate => formatPersonalPlateNumber(plateNumber);

  PersonalSavedVehicle copyWith({
    String? id,
    String? plateNumber,
    String? label,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool clearLastUsedAt = false,
  }) {
    return PersonalSavedVehicle(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'plateNumber': compactPlate,
      'label': label.trim(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
    };
  }

  factory PersonalSavedVehicle.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    final plate = normalizePersonalPlateNumber((map['plateNumber'] ?? '').toString());
    return PersonalSavedVehicle(
      id: (map['id'] ?? plate).toString(),
      plateNumber: plate,
      label: (map['label'] ?? '').toString(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()) ?? now,
      lastUsedAt: DateTime.tryParse((map['lastUsedAt'] ?? '').toString()),
    );
  }

  String encode() => jsonEncode(toMap());
}

String normalizePersonalPlateNumber(String value) {
  return value.trim().replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
}

String formatPersonalPlateNumber(String value) {
  final compact = normalizePersonalPlateNumber(value);
  final match = RegExp(r'^(\d{2,3})([가-힣])([0-9]{4})$').firstMatch(compact);
  if (match == null) return compact;
  return '${match.group(1)}${match.group(2)} ${match.group(3)}';
}

String personalVehicleIdFromPlate(String plateNumber) {
  final compact = normalizePersonalPlateNumber(plateNumber);
  return compact.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : compact;
}
