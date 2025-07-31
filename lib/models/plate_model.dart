import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../enums/plate_type.dart';
import 'plate_log_model.dart';

int parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class PlateFields {
  static const String plateNumber = 'plate_number';
  static const String plateFourDigit = 'plate_four_digit';
  static const String type = 'type';
  static const String requestTime = 'request_time';
  static const String endTime = 'end_time';
  static const String location = 'location';
  static const String area = 'area';
  static const String userName = 'userName';
  static const String isSelected = 'isSelected';
  static const String selectedBy = 'selectedBy';
  static const String billingType = 'billingType';
  static const String statusList = 'statusList';
  static const String basicStandard = 'basicStandard';
  static const String basicAmount = 'basicAmount';
  static const String addStandard = 'addStandard';
  static const String addAmount = 'addAmount';
  static const String region = 'region';
  static const String imageUrls = 'imageUrls';
  static const String isLockedFee = 'isLockedFee';
  static const String lockedAtTimeInSeconds = 'lockedAtTimeInSeconds';
  static const String lockedFeeAmount = 'lockedFeeAmount';
  static const String updatedAt = 'updatedAt';
  static const String paymentMethod = 'paymentMethod';
  static const String customStatus = 'customStatus';
  static const String logs = 'logs';
  static const String regularAmount = 'regularAmount';
  static const String regularDurationHours = 'regularDurationHours';
}

class PlateModel {
  final String id;
  final String plateNumber;
  final String plateFourDigit;
  final String type;
  final DateTime requestTime;
  final DateTime? endTime;
  final String location;
  final String area;
  final String userName;
  final bool isSelected;
  final String? selectedBy;
  final String? billingType;
  final List<String> statusList;
  final int? basicStandard;
  final int? basicAmount;
  final int? addStandard;
  final int? addAmount;
  final String? region;
  final List<String>? imageUrls;
  final bool isLockedFee;
  final int? lockedAtTimeInSeconds;
  final int? lockedFeeAmount;
  final DateTime? updatedAt;
  final String? paymentMethod;
  final String? customStatus;
  final List<PlateLogModel>? logs;
  final int? regularAmount;
  final int? regularDurationHours;

  PlateModel({
    required this.id,
    required this.plateNumber,
    required this.plateFourDigit,
    required this.type,
    required this.requestTime,
    this.endTime,
    required this.location,
    required this.area,
    required this.userName,
    this.isSelected = false,
    this.selectedBy,
    this.billingType,
    this.statusList = const [],
    this.basicStandard,
    this.basicAmount,
    this.addStandard,
    this.addAmount,
    this.region,
    this.imageUrls,
    this.isLockedFee = false,
    this.lockedAtTimeInSeconds,
    this.lockedFeeAmount,
    this.updatedAt,
    this.paymentMethod,
    this.customStatus,
    this.logs,
    this.regularAmount,
    this.regularDurationHours,
  });

  Map<String, dynamic> diff(PlateModel other) {
    final changes = <String, dynamic>{};

    if (plateNumber != other.plateNumber) {
      changes['plateNumber'] = {'before': plateNumber, 'after': other.plateNumber};
    }
    if (location != other.location) {
      changes['location'] = {'before': location, 'after': other.location};
    }
    if (billingType != other.billingType) {
      changes['billingType'] = {'before': billingType, 'after': other.billingType};
    }
    if (!listEquals(statusList, other.statusList)) {
      changes['statusList'] = {'before': statusList, 'after': other.statusList};
    }
    if (basicStandard != other.basicStandard) {
      changes['basicStandard'] = {'before': basicStandard, 'after': other.basicStandard};
    }
    if (basicAmount != other.basicAmount) {
      changes['basicAmount'] = {'before': basicAmount, 'after': other.basicAmount};
    }
    if (addStandard != other.addStandard) {
      changes['addStandard'] = {'before': addStandard, 'after': other.addStandard};
    }
    if (addAmount != other.addAmount) {
      changes['addAmount'] = {'before': addAmount, 'after': other.addAmount};
    }
    if (regularAmount != other.regularAmount) {
      changes['regularAmount'] = {'before': regularAmount, 'after': other.regularAmount};
    }
    if (regularDurationHours != other.regularDurationHours) {
      changes['regularDurationHours'] = {'before': regularDurationHours, 'after': other.regularDurationHours};
    }
    if (paymentMethod != other.paymentMethod) {
      changes['paymentMethod'] = {'before': paymentMethod, 'after': other.paymentMethod};
    }
    if (region != other.region) {
      changes['region'] = {'before': region, 'after': other.region};
    }
    if (customStatus != other.customStatus) {
      changes['customStatus'] = {'before': customStatus, 'after': other.customStatus};
    }

    return changes;
  }

  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final timestamp = data[PlateFields.requestTime];
    final endTimestamp = data[PlateFields.endTime];
    final updatedTimestamp = data[PlateFields.updatedAt];

    return PlateModel(
      id: doc.id,
      plateNumber: data[PlateFields.plateNumber] ?? '',
      plateFourDigit: data[PlateFields.plateFourDigit] ?? '',
      type: data[PlateFields.type] ?? '',
      requestTime: (timestamp is Timestamp) ? timestamp.toDate() : DateTime.now(),
      endTime: (endTimestamp is Timestamp) ? endTimestamp.toDate() : null,
      location: data[PlateFields.location] ?? '미지정',
      area: data[PlateFields.area] ?? '미지정',
      userName: data[PlateFields.userName] ?? 'Unknown',
      isSelected: data[PlateFields.isSelected] ?? false,
      selectedBy: data[PlateFields.selectedBy],
      billingType: data[PlateFields.billingType],
      statusList: List<String>.from(data[PlateFields.statusList] ?? []),
      basicStandard: parseInt(data[PlateFields.basicStandard]),
      basicAmount: parseInt(data[PlateFields.basicAmount]),
      addStandard: parseInt(data[PlateFields.addStandard]),
      addAmount: parseInt(data[PlateFields.addAmount]),
      region: data[PlateFields.region],
      imageUrls: List<String>.from(data[PlateFields.imageUrls] ?? []),
      isLockedFee: data[PlateFields.isLockedFee] ?? false,
      lockedAtTimeInSeconds: parseInt(data[PlateFields.lockedAtTimeInSeconds]),
      lockedFeeAmount: parseInt(data[PlateFields.lockedFeeAmount]),
      updatedAt: (updatedTimestamp is Timestamp) ? updatedTimestamp.toDate() : null,
      paymentMethod: data[PlateFields.paymentMethod],
      customStatus: data[PlateFields.customStatus],
      logs: (data[PlateFields.logs] as List?)?.map((e) => PlateLogModel.fromMap(Map<String, dynamic>.from(e))).toList(),
      regularAmount: parseInt(data[PlateFields.regularAmount]),
      regularDurationHours: parseInt(data[PlateFields.regularDurationHours]),
    );
  }

  Map<String, dynamic> toMap({bool removeNullOrEmpty = false}) {
    final map = {
      PlateFields.plateNumber: plateNumber,
      PlateFields.plateFourDigit: plateFourDigit,
      PlateFields.type: type,
      PlateFields.requestTime: requestTime,
      if (endTime != null) PlateFields.endTime: endTime,
      PlateFields.location: location,
      PlateFields.area: area,
      PlateFields.userName: userName,
      PlateFields.isSelected: isSelected,
      PlateFields.selectedBy: selectedBy,
      PlateFields.billingType: billingType,
      PlateFields.statusList: statusList,
      PlateFields.basicStandard: basicStandard,
      PlateFields.basicAmount: basicAmount,
      PlateFields.addStandard: addStandard,
      PlateFields.addAmount: addAmount,
      PlateFields.region: region,
      PlateFields.isLockedFee: isLockedFee,
      if (imageUrls != null) PlateFields.imageUrls: imageUrls,
      if (lockedAtTimeInSeconds != null) PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      if (lockedFeeAmount != null) PlateFields.lockedFeeAmount: lockedFeeAmount,
      if (updatedAt != null) PlateFields.updatedAt: Timestamp.fromDate(updatedAt!),
      if (paymentMethod != null) PlateFields.paymentMethod: paymentMethod,
      if (customStatus != null) PlateFields.customStatus: customStatus,
      if (logs != null) PlateFields.logs: logs!.map((e) => e.toMap()).toList(),
      if (regularAmount != null) PlateFields.regularAmount: regularAmount,
      if (regularDurationHours != null) PlateFields.regularDurationHours: regularDurationHours,
    };

    if (removeNullOrEmpty) {
      map.removeWhere((key, value) => value == null || (value is String && value.trim().isEmpty));
    }

    return map;
  }

  PlateModel copyWith({
    String? id,
    String? plateNumber,
    String? plateFourDigit,
    String? type,
    DateTime? requestTime,
    DateTime? endTime,
    String? location,
    String? area,
    String? userName,
    bool? isSelected,
    String? selectedBy,
    String? billingType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    String? region,
    List<String>? imageUrls,
    bool? isLockedFee,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? updatedAt,
    String? paymentMethod,
    String? customStatus,
    List<PlateLogModel>? logs,
    int? regularAmount,
    int? regularDurationHours,
  }) {
    return PlateModel(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      plateFourDigit: plateFourDigit ?? this.plateFourDigit,
      type: type ?? this.type,
      requestTime: requestTime ?? this.requestTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      area: area ?? this.area,
      userName: userName ?? this.userName,
      isSelected: isSelected ?? this.isSelected,
      selectedBy: selectedBy ?? this.selectedBy,
      billingType: billingType ?? this.billingType,
      statusList: statusList ?? this.statusList,
      basicStandard: basicStandard ?? this.basicStandard,
      basicAmount: basicAmount ?? this.basicAmount,
      addStandard: addStandard ?? this.addStandard,
      addAmount: addAmount ?? this.addAmount,
      region: region ?? this.region,
      imageUrls: imageUrls ?? this.imageUrls,
      isLockedFee: isLockedFee ?? this.isLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds ?? this.lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount ?? this.lockedFeeAmount,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      customStatus: customStatus ?? this.customStatus,
      logs: logs ?? this.logs,
      regularAmount: regularAmount ?? this.regularAmount,
      regularDurationHours: regularDurationHours ?? this.regularDurationHours,
    );
  }

  PlateModel addLog({
    required String action,
    required String performedBy,
    required String from,
    required String to,
    Map<String, dynamic>? updatedFields,
  }) {
    final newLog = PlateLogModel(
      plateNumber: plateNumber,
      division: type,
      area: area,
      from: from,
      to: to,
      action: action,
      performedBy: performedBy,
      billingType: billingType,
      timestamp: DateTime.now(),
      updatedFields: updatedFields,
    );

    final updatedLogs = List<PlateLogModel>.from(logs ?? [])..add(newLog);
    return copyWith(logs: updatedLogs);
  }

  @override
  String toString() => 'PlateModel(id: $id, plateNumber: $plateNumber, user: $userName, area: $area)';
}

extension PlateModelTypeExtension on PlateModel {
  PlateType? get typeEnum {
    switch (type) {
      case 'parking_requests':
        return PlateType.parkingRequests;
      case 'parking_completed':
        return PlateType.parkingCompleted;
      case 'departure_requests':
        return PlateType.departureRequests;
      case 'departure_completed':
        return PlateType.departureCompleted;
      default:
        return null;
    }
  }
}
