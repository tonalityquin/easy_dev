import 'package:flutter/material.dart';

/// 고정 제거 정책:
///  - '고정' 문자열 입력은 더 이상 지원하지 않으므로 안전하게 '변동'으로 치환
///  - '정기'는 기존 의미(월정기 등) 유지
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

  // 정기(월정기 등) 관련 값은 유지
  final int? regularAmount;
  final int? regularDurationHours;

  BillModel({
    required this.id,
    required this.countType,
    this.addAmount,
    this.addStandard,
    required this.area,
    this.basicAmount,
    this.basicStandard,
    this.regularAmount,
    this.regularDurationHours,
    required this.type,
  });

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
        regularDurationHours: (data['regularDurationHours'] is int)
            ? data['regularDurationHours']
            : int.tryParse(data['regularDurationHours']?.toString() ?? ''),
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
      'regularDurationHours': regularDurationHours,
      'type': billTypeToString(type), // '고정'이 아닌 '정기'/'변동'만 저장
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
      'regularDurationHours': regularDurationHours,
      'type': billTypeToString(type), // '고정' 미출력
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
      regularDurationHours: data['regularDurationHours'],
      type: billTypeFromString(data['type']), // '고정' 들어와도 general 로 안전 치환
    );
  }

  @override
  String toString() {
    return 'BillModel(id: $id, type: ${billTypeToString(type)}, countType: $countType, area: $area, '
        'basicStandard: $basicStandard, basicAmount: $basicAmount, addStandard: $addStandard, addAmount: $addAmount, '
        'regularAmount: $regularAmount, regularDurationHours: $regularDurationHours)';
  }
}
