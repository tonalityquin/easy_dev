import 'package:cloud_firestore/cloud_firestore.dart';

class PlateLogModel {
  final String action;
  final String area; // 모델엔 유지(메모리 상 보관 용도)
  final String? billingType;
  final String from;
  final String performedBy;
  final String plateNumber; // 모델엔 유지(메모리 상 보관 용도)
  final DateTime timestamp;
  final String to;
  final String type;
  final Map<String, dynamic>? updatedFields;

  // 추가: 선택 필드들
  final String? paymentMethod; // 결제 수단 (계좌/카드/현금)
  final int? lockedFee;        // 확정 요금 (로그 항목: lockedFee, 루트: lockedFeeAmount)
  final String? reason;        // 할증/할인 사유

  PlateLogModel({
    required this.action,
    required this.area,
    this.billingType,
    required this.from,
    required this.performedBy,
    required this.plateNumber,
    required this.timestamp,
    required this.to,
    required this.type,
    this.updatedFields,
    this.paymentMethod,
    this.lockedFee,
    this.reason,
  });

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'action': action,
      'from': from,
      'performedBy': performedBy,
      'timestamp': timestamp.toIso8601String(),
      'to': to,
    };

    final cleanBillingType = billingType?.trim();
    if (cleanBillingType != null && cleanBillingType.isNotEmpty) {
      map['billingType'] = cleanBillingType;
    }

    if (updatedFields != null && updatedFields!.isNotEmpty) {
      map['updatedFields'] = updatedFields;
    }

    if (paymentMethod != null && paymentMethod!.trim().isNotEmpty) {
      map['paymentMethod'] = paymentMethod;
    }
    if (lockedFee != null) {
      map['lockedFee'] = lockedFee;
    }
    if (reason != null && reason!.trim().isNotEmpty) {
      map['reason'] = reason!.trim();
    }

    return map;
  }

  static DateTime _parseTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) {
      // 밀리초로 간주(프로젝트 컨벤션에 맞게 필요 시 조정)
      return DateTime.fromMillisecondsSinceEpoch(ts);
    }
    if (ts is String) {
      return DateTime.tryParse(ts) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  factory PlateLogModel.fromMap(Map<String, dynamic> map) {
    final parsedTime = _parseTimestamp(map['timestamp']);

    Map<String, dynamic>? parsedUpdatedFields;
    final rawUpdatedFields = map['updatedFields'];
    if (rawUpdatedFields is Map) {
      try {
        parsedUpdatedFields = rawUpdatedFields.map((key, value) {
          if (value is Map) {
            return MapEntry(key, Map<String, dynamic>.from(value));
          } else {
            return MapEntry(key, {'value': value});
          }
        });
      } catch (_) {
        parsedUpdatedFields = null;
      }
    }

    return PlateLogModel(
      action: (map['action'] ?? '').toString(),
      area: (map['area'] ?? '').toString(),
      billingType: map['billingType'] as String?,
      from: (map['from'] ?? '').toString(),
      performedBy: (map['performedBy'] ?? '').toString(),
      plateNumber: (map['plateNumber'] ?? '').toString(),
      timestamp: parsedTime,
      to: (map['to'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      updatedFields: parsedUpdatedFields,
      paymentMethod: map['paymentMethod']?.toString(),
      lockedFee: _asInt(map['lockedFee'] ?? map['lockedFeeAmount']),
      reason: map['reason']?.toString(),
    );
  }

  @override
  String toString() {
    final pn = plateNumber.isNotEmpty ? plateNumber : '(no-plate)';
    return '[$timestamp] $pn moved from "$from" to "$to" by $performedBy '
        '(action: $action'
        '${billingType != null ? ', billingType: $billingType' : ''}'
        '${paymentMethod != null ? ', paymentMethod: $paymentMethod' : ''}'
        '${lockedFee != null ? ', lockedFee: $lockedFee' : ''}'
        '${reason != null ? ', reason: $reason' : ''}'
        ')';
  }
}
