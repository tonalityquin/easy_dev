import 'package:flutter/material.dart';
import 'bill_model.dart'; // enum BillType 정의되어 있는 파일

class RegularBillModel {
  final String id;
  final BillType type; // ✅ BillType.general or BillType.regular
  final String countType; // 정산 이름
  final String area;
  final String regularType; // '일 주차' or '월 주차'
  final int regularAmount; // 요금
  final int regularDurationHours; // 주차 가능 시간 (시간 단위)

  RegularBillModel({
    required this.id,
    this.type = BillType.regular, // 항상 정기
    required this.countType,
    required this.area,
    required this.regularType,
    required this.regularAmount,
    required this.regularDurationHours,
  });

  /// ✅ Firestore → 모델
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

  /// ✅ Firestore 저장용
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

  /// ✅ 캐시 저장용
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

  /// ✅ 캐시 복원용
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
