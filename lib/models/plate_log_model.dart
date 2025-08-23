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

  // ▼ 추가: 선택 필드들
  final String? paymentMethod; // 결제 수단 (예: 계좌/카드/현금)
  final int? lockedFee;        // 확정 요금 (로그 항목에 'lockedFee' 또는 별칭 'lockedFeeAmount')

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

    // ▼ 추가 필드 직렬화 (있을 때만)
    if (paymentMethod != null && paymentMethod!.trim().isNotEmpty) {
      map['paymentMethod'] = paymentMethod;
    }
    if (lockedFee != null) {
      map['lockedFee'] = lockedFee;
    }

    return map;
  }

  static DateTime _parseTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      return ts.toDate();
    } else if (ts is DateTime) {
      return ts;
    } else if (ts is int) {
      // int가 들어오면 밀리초로 가정 (기존 로직 유지해도 됨)
      return DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
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

      // ▼ 추가 필드 매핑
      paymentMethod: map['paymentMethod']?.toString(),
      // 로그 항목엔 'lockedFee', 문서 루트엔 'lockedFeeAmount'가 있을 수 있어 둘 다 대응
      lockedFee: _asInt(map['lockedFee'] ?? map['lockedFeeAmount']),
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
        ')';
  }
}
