import 'package:flutter/material.dart';

class AdjustmentModel {
  final String id;
  final String countType;
  final String area;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  AdjustmentModel({
    required this.id,
    required this.countType,
    required this.area,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  factory AdjustmentModel.fromMap(String id, Map<String, dynamic> data) {
    try {
      return AdjustmentModel(
        id: id,
        countType: data['CountType'] ?? '',
        area: data['area'] ?? '',
        basicStandard: (data['basicStandard'] is int)
            ? data['basicStandard']
            : int.tryParse(data['basicStandard'].toString()) ?? 0,
        basicAmount:
            (data['basicAmount'] is int) ? data['basicAmount'] : int.tryParse(data['basicAmount'].toString()) ?? 0,
        addStandard:
            (data['addStandard'] is int) ? data['addStandard'] : int.tryParse(data['addStandard'].toString()) ?? 0,
        addAmount: (data['addAmount'] is int) ? data['addAmount'] : int.tryParse(data['addAmount'].toString()) ?? 0,
      );
    } catch (e) {
      debugPrint("🔥 Firestore 데이터 변환 오류: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'CountType': countType,
      'area': area,
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
    };
  }

  @override
  String toString() {
    return 'AdjustmentModel(id: $id, countType: $countType, area: $area, basicStandard: $basicStandard, basicAmount: $basicAmount, addStandard: $addStandard, addAmount: $addAmount)';
  }
}
