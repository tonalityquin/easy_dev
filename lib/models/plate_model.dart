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
  static const String addAmount = 'addAmount';
  static const String addStandard = 'addStandard';
  static const String area = 'area';
  static const String basicAmount = 'basicAmount';
  static const String basicStandard = 'basicStandard';
  static const String billingType = 'billingType';
  static const String customStatus = 'customStatus';
  static const String endTime = 'end_time';

  static const String imageUrls = 'imageUrls';
  static const String isLockedFee = 'isLockedFee';
  static const String isSelected = 'isSelected';
  static const String location = 'location';
  static const String lockedAtTimeInSeconds = 'lockedAtTimeInSeconds';
  static const String lockedFeeAmount = 'lockedFeeAmount';
  static const String logs = 'logs';
  static const String paymentMethod = 'paymentMethod';
  static const String plateFourDigit = 'plate_four_digit';
  static const String plateNumber = 'plate_number';
  static const String region = 'region';
  static const String regularAmount = 'regularAmount';
  static const String regularDurationHours = 'regularDurationHours';
  static const String requestTime = 'request_time';
  static const String selectedBy = 'selectedBy';
  static const String statusList = 'statusList';
  static const String type = 'type';
  static const String updatedAt = 'updatedAt';
  static const String userAdjustment = 'userAdjustment';
  static const String userName = 'userName';

  static const String feeMode = 'feeMode';
}

class PlateModel {
  final String id;
  final int? addAmount;
  final int? addStandard;
  final String area;
  final int? basicAmount;
  final int? basicStandard;
  final String? billingType;
  final String? customStatus;
  final DateTime? endTime;
  final List<String>? imageUrls;
  final bool isLockedFee;
  final bool isSelected;
  final String location;
  final int? lockedAtTimeInSeconds;
  final int? lockedFeeAmount;
  final List<PlateLogModel>? logs;
  final String? paymentMethod;
  final String plateFourDigit;
  final String plateNumber;
  final String? region;
  final int? regularAmount;
  final int? regularDurationHours;
  final DateTime requestTime;
  final String? selectedBy;
  final List<String> statusList;
  final String type;
  final DateTime? updatedAt;
  final int? userAdjustment;
  final String userName;

  final String? feeMode;

  PlateModel({
    required this.id,
    this.addAmount,
    this.addStandard,
    required this.area,
    this.basicAmount,
    this.basicStandard,
    this.billingType,
    this.customStatus,
    this.endTime,
    this.imageUrls,
    this.isLockedFee = false,
    this.isSelected = false,
    required this.location,
    this.lockedFeeAmount,
    this.lockedAtTimeInSeconds,
    this.logs,
    this.paymentMethod,
    required this.plateFourDigit,
    required this.plateNumber,
    this.region,
    this.regularAmount,
    this.regularDurationHours,
    required this.requestTime,
    this.selectedBy,
    this.statusList = const [],
    required this.type,
    this.updatedAt,
    this.userAdjustment,
    required this.userName,
    this.feeMode,
  });

  /// getPlate, _queryPlates, streamToCurrentArea, subscribeType
  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final timestamp = data[PlateFields.requestTime];
    final endTimestamp = data[PlateFields.endTime];
    final updatedTimestamp = data[PlateFields.updatedAt];

    return PlateModel(
      id: doc.id,
      addAmount: parseInt(data[PlateFields.addAmount]),
      addStandard: parseInt(data[PlateFields.addStandard]),
      area: data[PlateFields.area] ?? '미지정',
      basicAmount: parseInt(data[PlateFields.basicAmount]),
      basicStandard: parseInt(data[PlateFields.basicStandard]),
      billingType: data[PlateFields.billingType],
      customStatus: data[PlateFields.customStatus],
      endTime: (endTimestamp is Timestamp) ? endTimestamp.toDate() : null,
      imageUrls: List<String>.from(data[PlateFields.imageUrls] ?? []),
      isLockedFee: data[PlateFields.isLockedFee] ?? false,
      isSelected: data[PlateFields.isSelected] ?? false,
      location: data[PlateFields.location] ?? '미지정',
      lockedAtTimeInSeconds: parseInt(data[PlateFields.lockedAtTimeInSeconds]),
      lockedFeeAmount: parseInt(data[PlateFields.lockedFeeAmount]),
      logs: (data[PlateFields.logs] as List?)?.map((e) => PlateLogModel.fromMap(Map<String, dynamic>.from(e))).toList(),
      paymentMethod: data[PlateFields.paymentMethod],
      plateFourDigit: data[PlateFields.plateFourDigit] ?? '',
      plateNumber: data[PlateFields.plateNumber] ?? '',
      region: data[PlateFields.region],
      regularAmount: parseInt(data[PlateFields.regularAmount]),
      regularDurationHours: parseInt(data[PlateFields.regularDurationHours]),
      requestTime: (timestamp is Timestamp) ? timestamp.toDate() : DateTime.now(),
      selectedBy: data[PlateFields.selectedBy],
      statusList: List<String>.from(data[PlateFields.statusList] ?? []),
      type: data[PlateFields.type] ?? '',
      updatedAt: (updatedTimestamp is Timestamp) ? updatedTimestamp.toDate() : null,
      userAdjustment: parseInt(data[PlateFields.userAdjustment]),
      userName: data[PlateFields.userName] ?? 'Unknown',
      feeMode: data[PlateFields.feeMode],
    );
  }

  /// addPlate, addOrUpdatePlate,
  Map<String, dynamic> toMap({bool removeNullOrEmpty = false}) {
    final map = {
      PlateFields.addAmount: addAmount,
      PlateFields.addStandard: addStandard,
      PlateFields.area: area,
      PlateFields.basicAmount: basicAmount,
      PlateFields.basicStandard: basicStandard,
      PlateFields.billingType: billingType,
      if (customStatus != null) PlateFields.customStatus: customStatus,
      if (endTime != null) PlateFields.endTime: endTime,
      if (imageUrls != null) PlateFields.imageUrls: imageUrls,
      PlateFields.isLockedFee: isLockedFee,
      PlateFields.isSelected: isSelected,
      PlateFields.location: location,
      if (lockedAtTimeInSeconds != null) PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      if (lockedFeeAmount != null) PlateFields.lockedFeeAmount: lockedFeeAmount,
      if (logs != null) PlateFields.logs: logs!.map((e) => e.toMap()).toList(),
      if (paymentMethod != null) PlateFields.paymentMethod: paymentMethod,
      PlateFields.plateFourDigit: plateFourDigit,
      PlateFields.plateNumber: plateNumber,
      PlateFields.region: region,
      if (regularAmount != null) PlateFields.regularAmount: regularAmount,
      if (regularDurationHours != null) PlateFields.regularDurationHours: regularDurationHours,
      PlateFields.requestTime: requestTime,
      PlateFields.selectedBy: selectedBy,
      PlateFields.statusList: statusList,
      PlateFields.type: type,
      if (updatedAt != null) PlateFields.updatedAt: Timestamp.fromDate(updatedAt!),
      if (userAdjustment != null) PlateFields.userAdjustment: userAdjustment,
      PlateFields.userName: userName,
      if (feeMode != null) PlateFields.feeMode: feeMode,
    };

    if (removeNullOrEmpty) {
      map.removeWhere((key, value) => value == null || (value is String && value.trim().isEmpty));
    }

    return map;
  }

  PlateModel copyWith({
    String? id,
    int? addAmount,
    int? addStandard,
    String? area,
    int? basicAmount,
    int? basicStandard,
    String? billingType,
    String? customStatus,
    DateTime? endTime,
    List<String>? imageUrls,
    bool? isLockedFee,
    bool? isSelected,
    String? location,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    List<PlateLogModel>? logs,
    String? paymentMethod,
    String? plateFourDigit,
    String? plateNumber,
    String? region,
    int? regularAmount,
    int? regularDurationHours,
    DateTime? requestTime,
    String? selectedBy,
    List<String>? statusList,
    String? type,
    DateTime? updatedAt,
    int? userAdjustment,
    String? userName,
    String? feeMode,
  }) {
    return PlateModel(
      id: id ?? this.id,
      addAmount: addAmount ?? this.addAmount,
      addStandard: addStandard ?? this.addStandard,
      area: area ?? this.area,
      basicAmount: basicAmount ?? this.basicAmount,
      basicStandard: basicStandard ?? this.basicStandard,
      billingType: billingType ?? this.billingType,
      customStatus: customStatus ?? this.customStatus,
      endTime: endTime ?? this.endTime,
      imageUrls: imageUrls ?? this.imageUrls,
      isLockedFee: isLockedFee ?? this.isLockedFee,
      isSelected: isSelected ?? this.isSelected,
      location: location ?? this.location,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds ?? this.lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount ?? this.lockedFeeAmount,
      logs: logs ?? this.logs,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      plateFourDigit: plateFourDigit ?? this.plateFourDigit,
      plateNumber: plateNumber ?? this.plateNumber,
      region: region ?? this.region,
      regularAmount: regularAmount ?? this.regularAmount,
      regularDurationHours: regularDurationHours ?? this.regularDurationHours,
      requestTime: requestTime ?? this.requestTime,
      selectedBy: selectedBy ?? this.selectedBy,
      statusList: statusList ?? this.statusList,
      type: type ?? this.type,
      updatedAt: updatedAt ?? this.updatedAt,
      userAdjustment: userAdjustment ?? this.userAdjustment,
      userName: userName ?? this.userName,
      feeMode: feeMode ?? this.feeMode,
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
      action: action,
      area: area,
      billingType: billingType,
      from: from,
      performedBy: performedBy,
      plateNumber: plateNumber,
      timestamp: DateTime.now(),
      to: to,
      type: type,
      updatedFields: updatedFields,
    );

    final updatedLogs = List<PlateLogModel>.from(logs ?? [])..add(newLog);
    return copyWith(logs: updatedLogs);
  }

  /// updatePlateInfo
  Map<String, dynamic> diff(PlateModel other) {
    final changes = <String, dynamic>{};
    if (addAmount != other.addAmount) {
      changes['addAmount'] = {'before': addAmount, 'after': other.addAmount};
    }
    if (addStandard != other.addStandard) {
      changes['addStandard'] = {'before': addStandard, 'after': other.addStandard};
    }
    if (basicAmount != other.basicAmount) {
      changes['basicAmount'] = {'before': basicAmount, 'after': other.basicAmount};
    }
    if (basicStandard != other.basicStandard) {
      changes['basicStandard'] = {'before': basicStandard, 'after': other.basicStandard};
    }
    if (billingType != other.billingType) {
      changes['billingType'] = {'before': billingType, 'after': other.billingType};
    }
    if (customStatus != other.customStatus) {
      changes['customStatus'] = {'before': customStatus, 'after': other.customStatus};
    }
    if (location != other.location) {
      changes['location'] = {'before': location, 'after': other.location};
    }
    if (paymentMethod != other.paymentMethod) {
      changes['paymentMethod'] = {'before': paymentMethod, 'after': other.paymentMethod};
    }
    if (plateNumber != other.plateNumber) {
      changes['plateNumber'] = {'before': plateNumber, 'after': other.plateNumber};
    }
    if (region != other.region) {
      changes['region'] = {'before': region, 'after': other.region};
    }
    if (regularAmount != other.regularAmount) {
      changes['regularAmount'] = {'before': regularAmount, 'after': other.regularAmount};
    }
    if (regularDurationHours != other.regularDurationHours) {
      changes['regularDurationHours'] = {'before': regularDurationHours, 'after': other.regularDurationHours};
    }
    if (!listEquals(statusList, other.statusList)) {
      changes['statusList'] = {'before': statusList, 'after': other.statusList};
    }

    if (userAdjustment != other.userAdjustment) {
      changes['userAdjustment'] = {'before': userAdjustment, 'after': other.userAdjustment};
    }
    if (feeMode != other.feeMode) {
      changes['feeMode'] = {'before': feeMode, 'after': other.feeMode};
    }

    return changes;
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
