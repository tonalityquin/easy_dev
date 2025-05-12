import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';

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
  static const String adjustmentType = 'adjustmentType';
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
  static const String paymentMethod = 'paymentMethod'; // ✅ 추가됨
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
  final String? adjustmentType;
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
  final String? paymentMethod; // ✅ 추가됨

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
    this.adjustmentType,
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
    this.paymentMethod, // ✅ 추가됨
  });

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
      adjustmentType: data[PlateFields.adjustmentType],
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
      paymentMethod: data[PlateFields.paymentMethod], // ✅ 추가됨
    );
  }

  Map<String, dynamic> toMap() {
    return {
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
      PlateFields.adjustmentType: adjustmentType,
      PlateFields.statusList: statusList,
      PlateFields.basicStandard: basicStandard,
      PlateFields.basicAmount: basicAmount,
      PlateFields.addStandard: addStandard,
      PlateFields.addAmount: addAmount,
      PlateFields.region: region,
      PlateFields.isLockedFee: isLockedFee,
      if (lockedAtTimeInSeconds != null)
        PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      if (lockedFeeAmount != null)
        PlateFields.lockedFeeAmount: lockedFeeAmount,
      if (updatedAt != null)
        PlateFields.updatedAt: Timestamp.fromDate(updatedAt!),
      if (paymentMethod != null)
        PlateFields.paymentMethod: paymentMethod, // ✅ 추가됨
    };
  }
  Map<String, dynamic> diff(PlateModel other) {
    final changes = <String, dynamic>{};

    if (location != other.location) {
      changes['location'] = {'before': location, 'after': other.location};
    }
    if (adjustmentType != other.adjustmentType) {
      changes['adjustmentType'] = {'before': adjustmentType, 'after': other.adjustmentType};
    }
    if (statusList.toString() != other.statusList.toString()) {
      changes['statusList'] = {'before': statusList, 'after': other.statusList};
    }
    if (paymentMethod != other.paymentMethod) {
      changes['paymentMethod'] = {'before': paymentMethod, 'after': other.paymentMethod};
    }
    if (lockedFeeAmount != other.lockedFeeAmount) {
      changes['lockedFeeAmount'] = {'before': lockedFeeAmount, 'after': other.lockedFeeAmount};
    }

    return changes;
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
    String? adjustmentType,
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
    String? paymentMethod, // ✅ 추가됨
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
      adjustmentType: adjustmentType ?? this.adjustmentType,
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
      paymentMethod: paymentMethod ?? this.paymentMethod, // ✅ 추가됨
    );
  }

  @override
  String toString() =>
      'PlateModel(id: $id, plateNumber: $plateNumber, user: $userName, area: $area)';
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
