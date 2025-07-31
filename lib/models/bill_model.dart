import 'package:flutter/material.dart';

/// ✅ BillType enum
enum BillType { general, regular }

/// ✅ 문자열 <-> enum 변환 유틸
BillType billTypeFromString(String? value) {
  switch (value) {
    case '정기':
      return BillType.regular;
    case '일반':
    default:
      return BillType.general;
  }
}

String billTypeToString(BillType type) {
  switch (type) {
    case BillType.regular:
      return '정기';
    case BillType.general:
      return '일반';
  }
}

/// ✅ BillModel 정의 (일반 + 정기 병합 구조)
class BillModel {
  final String id;
  final BillType type;
  final String countType;
  final String area;

  // 일반 정산
  final int? basicStandard;
  final int? basicAmount;
  final int? addStandard;
  final int? addAmount;

  // 정기 정산
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

  /// ✅ Firestore → 모델
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
        basicAmount: (data['basicAmount'] is int)
            ? data['basicAmount']
            : int.tryParse(data['basicAmount']?.toString() ?? ''),
        addStandard: (data['addStandard'] is int)
            ? data['addStandard']
            : int.tryParse(data['addStandard']?.toString() ?? ''),
        addAmount: (data['addAmount'] is int)
            ? data['addAmount']
            : int.tryParse(data['addAmount']?.toString() ?? ''),
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

  /// ✅ Firestore 저장용
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

  /// ✅ 캐시 저장용
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

  /// ✅ 캐시 복원용
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
