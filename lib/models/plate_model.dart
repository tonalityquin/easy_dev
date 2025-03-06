import 'package:cloud_firestore/cloud_firestore.dart';

/// 🔥 숫자 변환 유틸리티 함수
int parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Firestore 필드명을 상수화하여 관리
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

/// 차량 번호판 요청 데이터를 나타내는 모델 클래스
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

  /// Firestore 문서 데이터를 PlateModel 객체로 변환
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

  /// PlateModel 객체를 Map 형식으로 변환
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

  /// 객체 비교를 위한 `==` 연산자 오버라이딩
  /// 로그 개발용 셋업 - 서로 다른 컬렉션에 동일 정보의 document가 오가면 다른 객체로 인식하는 걸 오버라이딩을 통해 같은 객체로 인식하도록
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

  /// 해시코드 오버라이딩 (객체 비교 최적화)
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
