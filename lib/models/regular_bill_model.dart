import 'package:flutter/material.dart';
import 'bill_model.dart';

class RegularBillModel {
  final String id;
  final BillType type;
  final String countType;
  final String area;
  final String regularType;
  final int regularAmount;
  final int regularDurationHours;

  RegularBillModel({
    required this.id,
    this.type = BillType.regular,
    required this.countType,
    required this.area,
    required this.regularType,
    required this.regularAmount,
    required this.regularDurationHours,
  });

  factory RegularBillModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      return RegularBillModel(
        id: id,
        type: billTypeFromString(data['type']),
        countType: data['CountType'] ?? '',
        area: data['area'] ?? '',
        regularType: data['regularType'] ?? '',
        regularAmount: (data['regularAmount'] is int)
            ? data['regularAmount']
            : int.tryParse(data['regularAmount'].toString()) ?? 0,
        regularDurationHours: (data['regularDurationHours'] is int)
            ? data['regularDurationHours']
            : int.tryParse(data['regularDurationHours'].toString()) ?? 0,
      );
    } catch (e) {
      debugPrint("🔥 정기 정산 Firestore 변환 오류: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'type': billTypeToString(type),
      'CountType': countType,
      'area': area,
      'regularType': regularType,
      'regularAmount': regularAmount,
      'regularDurationHours': regularDurationHours,
    };
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'type': billTypeToString(type),
      'CountType': countType,
      'area': area,
      'regularType': regularType,
      'regularAmount': regularAmount,
      'regularDurationHours': regularDurationHours,
    };
  }

  factory RegularBillModel.fromCacheMap(Map<String, dynamic> data) {
    return RegularBillModel(
      id: data['id'] ?? '',
      type: billTypeFromString(data['type']),
      countType: data['CountType'] ?? '',
      area: data['area'] ?? '',
      regularType: data['regularType'] ?? '',
      regularAmount: data['regularAmount'] ?? 0,
      regularDurationHours: data['regularDurationHours'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'RegularBillModel(id: $id, type: ${billTypeToString(type)}, countType: $countType, area: $area, regularType: $regularType, regularAmount: $regularAmount, regularDurationHours: $regularDurationHours)';
  }
}
