import 'package:cloud_firestore/cloud_firestore.dart';

///  dynamic 타입의 value를 받아 정수로 변환하는 함수
int parseInt(dynamic value) {
  if (value is int) return value; // value가 이미 int 타입이면 그 값을 그대로 반환한다.
  if (value is String)
    return int.tryParse(value) ?? 0; // value가 String이면 'int.tryParse(value)'를 사용하여 정수로 변환한다. 변환 실패 시 0을 반환한다.
  return 0; // value가 int도 String도 아니면 기본값 0을 반환한다.
}

/// Firestore에서 사용될 필드명을 상수로 관리하는 클래스
class PlateFields {
  static const String plateNumber = 'plate_number';
  static const String type = 'type';
  static const String entryTime = 'entry_time';
  static const String location = 'location';
  static const String area = 'area';
  static const String userName = 'user_name';
  static const String isSelected = 'is_selected';
  static const String whoSelected = 'who_selected';
  static const String adjustmentType = 'adjustment_type';
  static const String memoList = 'memo_list';
  static const String basicStandard = 'basic_standard';
  static const String basicAmount = 'basic_amount';
  static const String addStandard = 'add_standard';
  static const String addAmount = 'add_amount';
}

/// 차량 정보를 Firestore에서 가져와 다루는 데이터 모델 역할의 클래스
class PlateModel {
  final String id;
  final String plateNumber;
  final String type;
  final DateTime entryTime;
  final String location;
  final String area;
  final String userName;
  final bool isSelected;
  final String? whoSelected;
  final String? adjustmentType;
  final List<String> memoList;
  final int? basicStandard;
  final int? basicAmount;
  final int? addStandard;
  final int? addAmount;

  /// 객체를 만들 때 필요한 데이터를 초기화하는 생성자
  /// required this = 필수값, this = 선택값
  PlateModel({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.entryTime,
    required this.location,
    required this.area,
    required this.userName,
    this.isSelected = false,
    this.whoSelected,
    this.adjustmentType,
    this.memoList = const [],
    this.basicStandard,
    this.basicAmount,
    this.addStandard,
    this.addAmount,
  });

  /// Firestore에서 가져온 DocumentSnapshot을 PlateModel 객체로 변환하는 생성자
  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data(); // Firestore doc에서 데이터를 가져와 Map<String, dynamic> 형태로 저장한다.
    final dynamic timestamp = data?[PlateFields.entryTime]; // Firestore에서 entry_time 필드를 가져와 timestamp 변수에 저장한다.

    return PlateModel(
      id: doc.id,
      plateNumber: data?[PlateFields.plateNumber] ?? '',
      type: data?[PlateFields.type] ?? '',
      entryTime: (timestamp is Timestamp) ? timestamp.toDate() : DateTime.now(),
      location: data?[PlateFields.location] ?? '미지정',
      area: data?[PlateFields.area] ?? '미지정',
      userName: data?[PlateFields.userName] ?? 'Unknown',
      isSelected: data?[PlateFields.isSelected] ?? false,
      whoSelected: data?[PlateFields.whoSelected],
      adjustmentType: data?[PlateFields.adjustmentType],
      memoList: (data?[PlateFields.memoList] is List) ? List<String>.from(data?[PlateFields.memoList]) : [],
      basicStandard: parseInt(data?[PlateFields.basicStandard]),
      basicAmount: parseInt(data?[PlateFields.basicAmount]),
      addStandard: parseInt(data?[PlateFields.addStandard]),
      addAmount: parseInt(data?[PlateFields.addAmount]),
    );
  }

  /// PlateModel 객체를 Firestore에 저장할 수 있도록 변환하는 함수
  Map<String, dynamic> toMap() {
    return {
      PlateFields.plateNumber: plateNumber,
      PlateFields.type: type,
      PlateFields.entryTime: entryTime,
      PlateFields.location: location,
      PlateFields.area: area,
      PlateFields.userName: userName,
      PlateFields.isSelected: isSelected,
      PlateFields.whoSelected: whoSelected,
      PlateFields.adjustmentType: adjustmentType,
      PlateFields.memoList: memoList.isNotEmpty ? memoList : [],
      PlateFields.basicStandard: basicStandard,
      PlateFields.basicAmount: basicAmount,
      PlateFields.addStandard: addStandard,
      PlateFields.addAmount: addAmount,
    };
  }

  ///  객체 비교(==) 연산자를 오버라이딩하여 PlateModel 객체를 비교할 때 각 필드 값이 동일한지 확인하는 함수
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true; // 같은 인스턴스라면 추가 비교 없이 바로 true 반환한다.

    return other is PlateModel &&
        other.id == id &&
        other.plateNumber == plateNumber &&
        other.type == type &&
        other.entryTime == entryTime &&
        other.location == location &&
        other.area == area &&
        other.userName == userName &&
        other.isSelected == isSelected &&
        other.whoSelected == whoSelected &&
        other.adjustmentType == adjustmentType &&
        other.memoList == memoList &&
        other.basicStandard == basicStandard &&
        other.basicAmount == basicAmount &&
        other.addStandard == addStandard &&
        other.addAmount == addAmount;
  }

  /// PlateModel 객체의 Hash Code를 생성하는 getter
  @override
  int get hashCode {
    return id.hashCode ^
        plateNumber.hashCode ^
        type.hashCode ^
        entryTime.hashCode ^
        location.hashCode ^
        area.hashCode ^
        userName.hashCode ^
        isSelected.hashCode ^
        whoSelected.hashCode ^
        adjustmentType.hashCode ^
        memoList.hashCode ^
        basicStandard.hashCode ^
        basicAmount.hashCode ^
        addStandard.hashCode ^
        addAmount.hashCode;
  }
}
