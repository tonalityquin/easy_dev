import 'package:cloud_firestore/cloud_firestore.dart';

int parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class PlateFields {
  static const String plateNumber = 'plate_number';
  static const String type = 'type';
  static const String requestTime = 'request_time';
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
  static const String lockedFeeAmount = 'lockedFeeAmount'; // ✅ 추가


}

class PlateModel {
  final String id;
  final String plateNumber;
  final String type;
  final DateTime requestTime;
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
  final bool isLockedFee; // ✅ 사전 정산 여부
  final int? lockedAtTimeInSeconds; // ✅ 정산 고정 시간 (초)
  final int? lockedFeeAmount; // ✅ 추가


  PlateModel({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.requestTime,
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
    this.lockedFeeAmount, // ✅

  });

  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final timestamp = data[PlateFields.requestTime];

    return PlateModel(
      id: doc.id,
      plateNumber: data[PlateFields.plateNumber] ?? '',
      type: data[PlateFields.type] ?? '',
      requestTime: (timestamp is Timestamp) ? timestamp.toDate() : DateTime.now(),
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
    );
  }

  factory PlateModel.fromMap(Map<String, dynamic> map, String id) {
    return PlateModel(
      id: id,
      plateNumber: map[PlateFields.plateNumber] ?? '',
      type: map[PlateFields.type] ?? '',
      requestTime: (map[PlateFields.requestTime] is Timestamp)
          ? (map[PlateFields.requestTime] as Timestamp).toDate()
          : DateTime.now(),
      location: map[PlateFields.location] ?? '미지정',
      area: map[PlateFields.area] ?? '미지정',
      userName: map[PlateFields.userName] ?? 'Unknown',
      isSelected: map[PlateFields.isSelected] ?? false,
      selectedBy: map[PlateFields.selectedBy],
      adjustmentType: map[PlateFields.adjustmentType],
      statusList: List<String>.from(map[PlateFields.statusList] ?? []),
      basicStandard: parseInt(map[PlateFields.basicStandard]),
      basicAmount: parseInt(map[PlateFields.basicAmount]),
      addStandard: parseInt(map[PlateFields.addStandard]),
      addAmount: parseInt(map[PlateFields.addAmount]),
      region: map[PlateFields.region],
      imageUrls: List<String>.from(map[PlateFields.imageUrls] ?? []),
      isLockedFee: map[PlateFields.isLockedFee] ?? false,
      lockedAtTimeInSeconds: parseInt(map[PlateFields.lockedAtTimeInSeconds]),
      lockedFeeAmount: parseInt(map[PlateFields.lockedFeeAmount]),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      PlateFields.plateNumber: plateNumber,
      PlateFields.type: type,
      PlateFields.requestTime: requestTime,
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
    };
  }

  PlateModel copyWith({
    String? id,
    String? plateNumber,
    String? type,
    DateTime? requestTime,
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
  }) {
    return PlateModel(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      type: type ?? this.type,
      requestTime: requestTime ?? this.requestTime,
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
      isLockedFee: isLockedFee ?? this.isLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds ?? this.lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount ?? this.lockedFeeAmount,
    );
  }

  @override
  String toString() =>
      'PlateModel(id: $id, plateNumber: $plateNumber, user: $userName, area: $area)';
}
