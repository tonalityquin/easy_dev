import 'package:flutter/material.dart';

enum BillType { general, regular }

BillType billTypeFromString(String? value) {
  switch (value) {
    case '고정':
      return BillType.regular;
    case '변동':
    default:
      return BillType.general;
  }
}

String billTypeToString(BillType type) {
  switch (type) {
    case BillType.regular:
      return '고정';
    case BillType.general:
      return '변동';
  }
}

class BillModel {
  final String id;
  final BillType type;
  final String countType;
  final String area;

  final int? basicStandard;
  final int? basicAmount;
  final int? addStandard;
  final int? addAmount;

  final int? regularAmount;
  final int? regularDurationHours;

  BillModel({
    required this.id,
    required this.type,
    required this.countType,
    required this.area,
    this.basicStandard,
    this.basicAmount,
    this.addStandard,
    this.addAmount,
    this.regularAmount,
    this.regularDurationHours,
  });

  factory BillModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      final type = billTypeFromString(data['type']);
      return BillModel(
        id: id,
        type: type,
        countType: data['CountType'] ?? '',
        area: data['area'] ?? '',
        basicStandard: (data['basicStandard'] is int)
            ? data['basicStandard']
            : int.tryParse(data['basicStandard']?.toString() ?? ''),
        basicAmount:
            (data['basicAmount'] is int) ? data['basicAmount'] : int.tryParse(data['basicAmount']?.toString() ?? ''),
        addStandard:
            (data['addStandard'] is int) ? data['addStandard'] : int.tryParse(data['addStandard']?.toString() ?? ''),
        addAmount: (data['addAmount'] is int) ? data['addAmount'] : int.tryParse(data['addAmount']?.toString() ?? ''),
        regularAmount: (data['regularAmount'] is int)
            ? data['regularAmount']
            : int.tryParse(data['regularAmount']?.toString() ?? ''),
        regularDurationHours: (data['regularDurationHours'] is int)
            ? data['regularDurationHours']
            : int.tryParse(data['regularDurationHours']?.toString() ?? ''),
      );
    } catch (e) {
      debugPrint("🔥 Firestore BillModel 변환 오류: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'type': billTypeToString(type),
      'CountType': countType,
      'area': area,
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
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
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
      'regularAmount': regularAmount,
      'regularDurationHours': regularDurationHours,
    };
  }

  factory BillModel.fromCacheMap(Map<String, dynamic> data) {
    return BillModel(
      id: data['id'] ?? '',
      type: billTypeFromString(data['type']),
      countType: data['CountType'] ?? '',
      area: data['area'] ?? '',
      basicStandard: data['basicStandard'],
      basicAmount: data['basicAmount'],
      addStandard: data['addStandard'],
      addAmount: data['addAmount'],
      regularAmount: data['regularAmount'],
      regularDurationHours: data['regularDurationHours'],
    );
  }

  @override
  String toString() {
    return 'BillModel(id: $id, type: ${billTypeToString(type)}, countType: $countType, area: $area, '
        'basicStandard: $basicStandard, basicAmount: $basicAmount, addStandard: $addStandard, addAmount: $addAmount, '
        'regularAmount: $regularAmount, regularDurationHours: $regularDurationHours)';
  }
}
