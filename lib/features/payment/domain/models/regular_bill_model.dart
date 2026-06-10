import 'package:flutter/material.dart';
import 'bill_model.dart';

class RegularBillModel {
  final String id;
  final String countType;
  final String area;
  final int regularAmount;
  final int regularDurationValue;
  final String regularType;
  final BillType type;

  RegularBillModel({
    required this.id,
    required this.countType,
    required this.area,
    required this.regularAmount,
    int? regularDurationValue,
    int? regularDurationHours,
    required this.regularType,
    this.type = BillType.regular,
  }) : regularDurationValue = regularDurationValue ?? regularDurationHours ?? 0;

  int get regularDurationHours => regularDurationValue;

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory RegularBillModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      return RegularBillModel(
        id: id,
        countType: data['CountType'] ?? '',
        area: data['area'] ?? '',
        regularAmount: _readInt(data['regularAmount']),
        regularDurationValue: _readInt(data['regularDurationValue'] ?? data['regularDurationHours']),
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
      'regularDurationValue': regularDurationValue,
      'regularDurationHours': regularDurationValue,
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
      'regularDurationValue': regularDurationValue,
      'regularDurationHours': regularDurationValue,
      'regularType': regularType,
      'type': billTypeToString(type),
    };
  }

  factory RegularBillModel.fromCacheMap(Map<String, dynamic> data) {
    return RegularBillModel(
      id: data['id'] ?? '',
      countType: data['CountType'] ?? '',
      area: data['area'] ?? '',
      regularAmount: _readInt(data['regularAmount']),
      regularDurationValue: _readInt(data['regularDurationValue'] ?? data['regularDurationHours']),
      regularType: data['regularType'] ?? '',
      type: billTypeFromString(data['type']),
    );
  }

  @override
  String toString() {
    return 'RegularBillModel(id: $id, type: ${billTypeToString(type)}, countType: $countType, area: $area, regularType: $regularType, regularAmount: $regularAmount, regularDurationValue: $regularDurationValue)';
  }
}
