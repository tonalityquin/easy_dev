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
  });

  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    final dynamic timestamp = data?[PlateFields.requestTime];

    return PlateModel(
      id: doc.id,
      plateNumber: data?[PlateFields.plateNumber] ?? '',
      type: data?[PlateFields.type] ?? '',
      requestTime: (timestamp is Timestamp) ? timestamp.toDate() : DateTime.now(),
      location: data?[PlateFields.location] ?? '미지정',
      area: data?[PlateFields.area] ?? '미지정',
      userName: data?[PlateFields.userName] ?? 'Unknown',
      isSelected: data?[PlateFields.isSelected] ?? false,
      selectedBy: data?[PlateFields.selectedBy],
      adjustmentType: data?[PlateFields.adjustmentType],
      statusList: (data?[PlateFields.statusList] is List) ? List<String>.from(data?[PlateFields.statusList]) : [],
      basicStandard: parseInt(data?[PlateFields.basicStandard]),
      basicAmount: parseInt(data?[PlateFields.basicAmount]),
      addStandard: parseInt(data?[PlateFields.addStandard]),
      addAmount: parseInt(data?[PlateFields.addAmount]),
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
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PlateModel &&
        other.id == id &&
        other.plateNumber == plateNumber &&
        other.type == type &&
        other.requestTime == requestTime &&
        other.location == location &&
        other.area == area &&
        other.userName == userName &&
        other.isSelected == isSelected &&
        other.selectedBy == selectedBy &&
        other.adjustmentType == adjustmentType &&
        other.statusList == statusList &&
        other.basicStandard == basicStandard &&
        other.basicAmount == basicAmount &&
        other.addStandard == addStandard &&
        other.addAmount == addAmount;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        plateNumber.hashCode ^
        type.hashCode ^
        requestTime.hashCode ^
        location.hashCode ^
        area.hashCode ^
        userName.hashCode ^
        isSelected.hashCode ^
        selectedBy.hashCode ^
        adjustmentType.hashCode ^
        statusList.hashCode ^
        basicStandard.hashCode ^
        basicAmount.hashCode ^
        addStandard.hashCode ^
        addAmount.hashCode;
  }
}
