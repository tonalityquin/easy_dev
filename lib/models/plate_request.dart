import 'package:cloud_firestore/cloud_firestore.dart';

/// **PlateRequest 클래스**
/// - 차량 번호판 요청 데이터를 나타내는 모델 클래스
class PlateRequest {
  final String id;
  final String plateNumber;
  final String type;
  final DateTime requestTime;
  final String location;
  final String area;

  PlateRequest({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.requestTime,
    required this.location,
    required this.area,
  });

  /// Firestore 문서에서 객체 생성
  factory PlateRequest.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final dynamic timestamp = doc['request_time'];
    return PlateRequest(
      id: doc.id,
      plateNumber: doc['plate_number'],
      type: doc['type'],
      requestTime: (timestamp is Timestamp)
          ? timestamp.toDate()
          : (timestamp is DateTime)
          ? timestamp
          : DateTime.now(),
      location: doc['location'] ?? '미지정',
      area: doc.data()?.containsKey('area') == true ? doc['area'] : '미지정', // "area" 필드가 없으면 기본값 사용
    );
  }

  /// 객체를 Firestore에 저장 가능한 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'plate_number': plateNumber,
      'type': type,
      'request_time': requestTime,
      'location': location,
      'area': area,
    };
  }
}
