// ==============================
// File: offline_bill_model.dart
// ==============================
import 'package:flutter/foundation.dart';

@immutable
class OfflineBill {
  final int? id;
  final String billKey;        // 예: "무료_가로수길(캔버스랩)"
  final String area;           // 예: "가로수길(캔버스랩)"
  final String countType;      // 예: "무료"
  final String type;           // 예: "변동"
  final int basicAmount;       // 예: 0
  final int basicStandard;     // 예: 1
  final int addAmount;         // 예: 0
  final int addStandard;       // 예: 1
  final DateTime? updatedAt;   // ms epoch ↔ DateTime
  final DateTime? createdAt;   // ms epoch ↔ DateTime

  const OfflineBill({
    this.id,
    required this.billKey,
    required this.area,
    required this.countType,
    required this.type,
    this.basicAmount = 0,
    this.basicStandard = 1,
    this.addAmount = 0,
    this.addStandard = 1,
    this.updatedAt,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'bill_key': billKey,
    'area': area,
    'count_type': countType,
    'type': type,
    'basic_amount': basicAmount,
    'basic_standard': basicStandard,
    'add_amount': addAmount,
    'add_standard': addStandard,
    'updated_at': updatedAt?.millisecondsSinceEpoch,
    'created_at': createdAt?.millisecondsSinceEpoch,
  }..removeWhere((k, v) => v == null);

  factory OfflineBill.fromMap(Map<String, Object?> map) => OfflineBill(
    id: map['id'] as int?,
    billKey: (map['bill_key'] ?? '') as String,
    area: (map['area'] ?? '') as String,
    countType: (map['count_type'] ?? '') as String,
    type: (map['type'] ?? '') as String,
    basicAmount: (map['basic_amount'] as int?) ?? 0,
    basicStandard: (map['basic_standard'] as int?) ?? 1,
    addAmount: (map['add_amount'] as int?) ?? 0,
    addStandard: (map['add_standard'] as int?) ?? 1,
    updatedAt: (map['updated_at'] as int?) != null
        ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
        : null,
    createdAt: (map['created_at'] as int?) != null
        ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
        : null,
  );

  static String makeBillKey({required String countType, required String area}) =>
      '${countType}_${area}';
}
