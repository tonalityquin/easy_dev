import 'package:flutter/material.dart';

enum BillType { general, regular }

BillType billTypeFromString(String? value) {
  switch (value) {
    case '정기':
      return BillType.regular;
    case '고정':
      return BillType.general;
    case '변동':
    default:
      return BillType.general;
  }
}

String billTypeToString(BillType type) {
  switch (type) {
    case BillType.regular:
      return '정기';
    case BillType.general:
      return '변동';
  }
}

class BillModel {
  final String id;
  final String countType;
  final int? addAmount;
  final int? addStandard;
  final String area;
  final int? basicAmount;
  final int? basicStandard;
  final BillType type;

  final int? regularAmount;
  final int? regularDurationValue;

  BillModel({
    required this.id,
    required this.countType,
    this.addAmount,
    this.addStandard,
    required this.area,
    this.basicAmount,
    this.basicStandard,
    this.regularAmount,
    int? regularDurationValue,
    int? regularDurationHours,
    required this.type,
  }) : regularDurationValue = regularDurationValue ?? regularDurationHours;

  int? get regularDurationHours => regularDurationValue;

  factory BillModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      final type = billTypeFromString(data['type']);
      return BillModel(
        id: id,
        countType: data['CountType'] ?? '',
        addAmount: (data['addAmount'] is int)
            ? data['addAmount']
            : int.tryParse(data['addAmount']?.toString() ?? ''),
        addStandard: (data['addStandard'] is int)
            ? data['addStandard']
            : int.tryParse(data['addStandard']?.toString() ?? ''),
        area: data['area'] ?? '',
        basicAmount: (data['basicAmount'] is int)
            ? data['basicAmount']
            : int.tryParse(data['basicAmount']?.toString() ?? ''),
        basicStandard: (data['basicStandard'] is int)
            ? data['basicStandard']
            : int.tryParse(data['basicStandard']?.toString() ?? ''),
        regularAmount: (data['regularAmount'] is int)
            ? data['regularAmount']
            : int.tryParse(data['regularAmount']?.toString() ?? ''),
        regularDurationValue: (data['regularDurationValue'] is int)
            ? data['regularDurationValue']
            : int.tryParse((data['regularDurationValue'] ?? data['regularDurationHours'])?.toString() ?? ''),
        type: type,
      );
    } catch (e) {
      debugPrint("🔥 Firestore BillModel 변환 오류: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'CountType': countType,
      'addAmount': addAmount,
      'addStandard': addStandard,
      'area': area,
      'basicAmount': basicAmount,
      'basicStandard': basicStandard,
      'regularAmount': regularAmount,
      'regularDurationValue': regularDurationValue,
      'regularDurationHours': regularDurationValue,
      'type': billTypeToString(type),
    };
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'CountType': countType,
      'addAmount': addAmount,
      'addStandard': addStandard,
      'area': area,
      'basicAmount': basicAmount,
      'basicStandard': basicStandard,
      'regularAmount': regularAmount,
      'regularDurationValue': regularDurationValue,
      'regularDurationHours': regularDurationValue,
      'type': billTypeToString(type),
    };
  }

  factory BillModel.fromCacheMap(Map<String, dynamic> data) {
    return BillModel(
      id: data['id'] ?? '',
      countType: data['CountType'] ?? '',
      addAmount: data['addAmount'],
      addStandard: data['addStandard'],
      area: data['area'] ?? '',
      basicAmount: data['basicAmount'],
      basicStandard: data['basicStandard'],
      regularAmount: data['regularAmount'],
      regularDurationValue: data['regularDurationValue'] ?? data['regularDurationHours'],
      type: billTypeFromString(data['type']),
    );
  }

  @override
  String toString() {
    return 'BillModel(id: $id, type: ${billTypeToString(type)}, countType: $countType, area: $area, '
        'basicStandard: $basicStandard, basicAmount: $basicAmount, addStandard: $addStandard, addAmount: $addAmount, '
        'regularAmount: $regularAmount, regularDurationValue: $regularDurationValue)';
  }
}
