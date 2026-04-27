import 'package:cloud_firestore/cloud_firestore.dart';

class PlateLogModel {
  final String action;
  final String area;
  final String? billingType;
  final String from;
  final String performedBy;
  final String plateNumber;
  final DateTime timestamp;
  final String to;
  final String type;
  final Map<String, dynamic>? updatedFields;

  final String? paymentMethod;
  final int? lockedFee;
  final String? reason;

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
