// ==============================
// File: offline_plate_model.dart
// ==============================
import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class OfflinePlate {
  final int? id;
  final String plateKey;           // plate_number + '_' + area
  final String plateNumber;
  final String? plateFourDigit;
  final String? region;
  final String? area;
  final String? location;
  final String? billingType;
  final String? customStatus;
  final int basicAmount;
  final int basicStandard;
  final int addAmount;
  final int addStandard;
  final bool isLockedFee;
  final int lockedFeeAmount;
  final int? lockedAtSeconds;
  final bool isSelected;
  final String? statusType;
  final DateTime? updatedAt;
  final String? requestTime;
  final String? userName;
  final String? selectedBy;
  final int userAdjustment;
  final int regularAmount;
  final int regularDurationHours;
  final List<String> imageUrls;
  final List<Map<String, dynamic>> logs;
  final DateTime? createdAt;

  const OfflinePlate({
    this.id,
    required this.plateKey,
    required this.plateNumber,
    this.plateFourDigit,
    this.region,
    this.area,
    this.location,
    this.billingType,
    this.customStatus,
    this.basicAmount = 0,
    this.basicStandard = 0,
    this.addAmount = 0,
    this.addStandard = 0,
    this.isLockedFee = false,
    this.lockedFeeAmount = 0,
    this.lockedAtSeconds,
    this.isSelected = false,
    this.statusType,
    this.updatedAt,
    this.requestTime,
    this.userName,
    this.selectedBy,
    this.userAdjustment = 0,
    this.regularAmount = 0,
    this.regularDurationHours = 0,
    this.imageUrls = const [],
    this.logs = const [],
    this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'plate_key': plateKey,
      'plate_number': plateNumber,
      'plate_four_digit': plateFourDigit,
      'region': region,
      'area': area,
      'location': location,
      'billing_type': billingType,
      'custom_status': customStatus,
      'basic_amount': basicAmount,
      'basic_standard': basicStandard,
      'add_amount': addAmount,
      'add_standard': addStandard,
      'is_locked_fee': isLockedFee ? 1 : 0,
      'locked_fee_amount': lockedFeeAmount,
      'locked_at_seconds': lockedAtSeconds,
      'is_selected': isSelected ? 1 : 0,
      'status_type': statusType,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'request_time': requestTime,
      'user_name': userName,
      'selected_by': selectedBy,
      'user_adjustment': userAdjustment,
      'regular_amount': regularAmount,
      'regular_duration_hours': regularDurationHours,
      'image_urls': jsonEncode(imageUrls),
      'logs': jsonEncode(logs),
      'created_at': createdAt?.millisecondsSinceEpoch,
    }..removeWhere((k, v) => v == null);
  }

  factory OfflinePlate.fromMap(Map<String, Object?> map) {
    List<String> _readImages(Object? v) {
      if (v == null) return [];
      try {
        final decoded = jsonDecode(v as String);
        return (decoded as List).map((e) => e?.toString() ?? '').toList();
      } catch (_) {
        return [];
      }
    }

    List<Map<String, dynamic>> _readLogs(Object? v) {
      if (v == null) return [];
      try {
        final decoded = jsonDecode(v as String);
        return (decoded as List)
            .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
            .cast<Map<String, dynamic>>()
            .toList();
      } catch (_) {
        return [];
      }
    }

    return OfflinePlate(
      id: map['id'] as int?,
      plateKey: (map['plate_key'] ?? '') as String,
      plateNumber: (map['plate_number'] ?? '') as String,
      plateFourDigit: map['plate_four_digit'] as String?,
      region: map['region'] as String?,
      area: map['area'] as String?,
      location: map['location'] as String?,
      billingType: map['billing_type'] as String?,
      customStatus: map['custom_status'] as String?,
      basicAmount: (map['basic_amount'] as int?) ?? 0,
      basicStandard: (map['basic_standard'] as int?) ?? 0,
      addAmount: (map['add_amount'] as int?) ?? 0,
      addStandard: (map['add_standard'] as int?) ?? 0,
      isLockedFee: ((map['is_locked_fee'] as int?) ?? 0) == 1,
      lockedFeeAmount: (map['locked_fee_amount'] as int?) ?? 0,
      lockedAtSeconds: map['locked_at_seconds'] as int?,
      isSelected: ((map['is_selected'] as int?) ?? 0) == 1,
      statusType: map['status_type'] as String?,
      updatedAt: (map['updated_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      requestTime: map['request_time'] as String?,
      userName: map['user_name'] as String?,
      selectedBy: map['selected_by'] as String?,
      userAdjustment: (map['user_adjustment'] as int?) ?? 0,
      regularAmount: (map['regular_amount'] as int?) ?? 0,
      regularDurationHours: (map['regular_duration_hours'] as int?) ?? 0,
      imageUrls: _readImages(map['image_urls']),
      logs: _readLogs(map['logs']),
      createdAt: (map['created_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : null,
    );
  }

  static String makePlateKey({required String plateNumber, required String area}) =>
      '${plateNumber}_${area}';
}
