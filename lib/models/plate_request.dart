import 'package:cloud_firestore/cloud_firestore.dart';

/// 차량 번호판 요청 데이터를 나타내는 모델 클래스
class PlateRequest {
  final String id; // Firestore 문서 ID
  final String plateNumber; // 차량 번호판
  final String type; // 요청 유형
  final DateTime requestTime; // 요청 시간
  final String location; // 요청 위치
  final String area; // 요청 지역

  PlateRequest({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.requestTime,
    required this.location,
    required this.area,
  });

  /// Firestore 문서 데이터를 PlateRequest 객체로 변환
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
      area: doc.data()?.containsKey('area') == true ? doc['area'] : '미지정',
    );
  }

  /// PlateRequest 객체를 Map 형식으로 변환
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
