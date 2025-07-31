import 'package:flutter/material.dart';

class BillModel {
  final String id;
  final String type; // ✅ 일반 / 정기 구분 필드
  final String countType;
  final String area;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  BillModel({
    required this.id,
    required this.type,
    required this.countType,
    required this.area,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  /// ✅ Firestore → 모델
  factory BillModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      return BillModel(
        id: id,
        type: data['type'] ?? '일반', // 기본값으로 '일반'
        countType: data['CountType'] ?? '',
        area: data['area'] ?? '',
        basicStandard: (data['basicStandard'] is int)
            ? data['basicStandard']
            : int.tryParse(data['basicStandard'].toString()) ?? 0,
        basicAmount: (data['basicAmount'] is int)
            ? data['basicAmount']
            : int.tryParse(data['basicAmount'].toString()) ?? 0,
        addStandard: (data['addStandard'] is int)
            ? data['addStandard']
            : int.tryParse(data['addStandard'].toString()) ?? 0,
        addAmount: (data['addAmount'] is int)
            ? data['addAmount']
            : int.tryParse(data['addAmount'].toString()) ?? 0,
      );
    } catch (e) {
      debugPrint("🔥 Firestore 데이터 변환 오류: $e");
      rethrow;
    }
  }

  /// ✅ Firestore 저장용
  Map<String, dynamic> toFirestoreMap() {
    return {
      'type': type,
      'CountType': countType,
      'area': area,
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
    };
  }

  /// ✅ 캐시 저장용
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'type': type,
      'CountType': countType,
      'area': area,
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
    };
  }

  /// ✅ 캐시 복원용
  factory BillModel.fromCacheMap(Map<String, dynamic> data) {
    return BillModel(
      id: data['id'] ?? '',
      type: data['type'] ?? '일반',
      countType: data['CountType'] ?? '',
      area: data['area'] ?? '',
      basicStandard: data['basicStandard'] ?? 0,
      basicAmount: data['basicAmount'] ?? 0,
      addStandard: data['addStandard'] ?? 0,
      addAmount: data['addAmount'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'BillModel(id: $id, type: $type, countType: $countType, area: $area, basicStandard: $basicStandard, basicAmount: $basicAmount, addStandard: $addStandard, addAmount: $addAmount)';
  }
}
