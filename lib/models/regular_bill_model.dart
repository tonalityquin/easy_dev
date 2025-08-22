import 'package:flutter/material.dart';
import 'bill_model.dart';

class RegularBillModel {
  final String id;
  final String countType;
  final String area;
  final int regularAmount;
  final int regularDurationHours;
  final String regularType;
  final BillType type;

  RegularBillModel({
    required this.id,
    required this.countType,
    required this.area,
    required this.regularAmount,
    required this.regularDurationHours,
    required this.regularType,
    this.type = BillType.regular,
  });

  factory RegularBillModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      return RegularBillModel(
        id: id,
        countType: data['CountType'] ?? '',
        area: data['area'] ?? '',
        regularAmount: (data['regularAmount'] is int)
            ? data['regularAmount']
            : int.tryParse(data['regularAmount'].toString()) ?? 0,
        regularDurationHours: (data['regularDurationHours'] is int)
            ? data['regularDurationHours']
            : int.tryParse(data['regularDurationHours'].toString()) ?? 0,
        regularType: data['regularType'] ?? '',
        type: billTypeFromString(data['type']),
      );
    } catch (e) {
      debugPrint("🔥 정기 정산 Firestore 변환 오류: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'CountType': countType,
      'area': area,
      'regularAmount': regularAmount,
      'regularDurationHours': regularDurationHours,
      'regularType': regularType,
      'type': billTypeToString(type),
    };
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'CountType': countType,
      'area': area,
      'regularAmount': regularAmount,
      'regularDurationHours': regularDurationHours,
      'regularType': regularType,
      'type': billTypeToString(type),
    };
  }

  factory RegularBillModel.fromCacheMap(Map<String, dynamic> data) {
    return RegularBillModel(
      id: data['id'] ?? '',
      countType: data['CountType'] ?? '',
      area: data['area'] ?? '',
      regularAmount: data['regularAmount'] ?? 0,
      regularDurationHours: data['regularDurationHours'] ?? 0,
      regularType: data['regularType'] ?? '',
      type: billTypeFromString(data['type']),
    );
  }

  @override
  String toString() {
    return 'RegularBillModel(id: $id, type: ${billTypeToString(type)}, countType: $countType, area: $area, regularType: $regularType, regularAmount: $regularAmount, regularDurationHours: $regularDurationHours)';
  }
}
