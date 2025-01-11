import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// **PlateRequest 클래스**
/// - 차량 번호판 요청 데이터를 나타내는 모델 클래스
class PlateRequest {
  final String id; // 문서 ID
  final String plateNumber; // 차량 번호판
  final String type; // 요청 상태 (예: 입차 요청, 입차 완료)
  final DateTime requestTime; // 요청 시간
  final String location; // 요청 위치

  /// **PlateRequest 생성자**
  PlateRequest({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.requestTime,
    required this.location,
  });

  /// **Firestore 문서에서 PlateRequest 생성**
  /// [doc]: Firestore QueryDocumentSnapshot
  factory PlateRequest.fromDocument(QueryDocumentSnapshot doc) {
    final dynamic timestamp = doc['request_time'];
    return PlateRequest(
      id: doc.id,
      plateNumber: doc['plate_number'],
      type: doc['type'],
      requestTime: (timestamp is Timestamp)
          ? timestamp.toDate() // Timestamp 형식 변환
          : (timestamp is DateTime)
              ? timestamp // DateTime 형식 유지
              : DateTime.now(),
      // 기본값
      location: doc['location'],
    );
  }

  /// **PlateRequest 데이터를 Map으로 변환**
  Map<String, dynamic> toMap() {
    return {
      'plate_number': plateNumber,
      'type': type,
      'request_time': requestTime,
      'location': location,
    };
  }
}

/// **PlateState 클래스**
/// - 차량 번호판 데이터 상태 관리
/// - Firestore와 실시간 데이터 동기화
class PlateState extends ChangeNotifier {
  // Firestore 컬렉션별 데이터 관리
  final Map<String, List<PlateRequest>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  // 현재 운전 중인 차량 번호판
  String? isDrivingPlate;

  // 입차 요청 데이터
  List<PlateRequest> get parkingRequests => _data['parking_requests']!;

  // 입차 완료 데이터
  List<PlateRequest> get parkingCompleted => _data['parking_completed']!;

  // 출차 요청 데이터
  List<PlateRequest> get departureRequests => _data['departure_requests']!;

  // 출차 완료 데이터
  List<PlateRequest> get departureCompleted => _data['departure_completed']!;

  /// **생성자**
  /// - Firestore 데이터 구독 초기화
  PlateState() {
    _initializeSubscriptions();
  }

  /// **Firestore 데이터 구독 초기화**
  /// - 각 컬렉션의 데이터를 실시간으로 수신
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      FirebaseFirestore.instance.collection(collectionName).snapshots().listen((snapshot) {
        _data[collectionName]!.clear();
        _data[collectionName]!.addAll(
          snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList(),
        );
        notifyListeners(); // 상태 변경 알림
      });
    }
  }

  /// **번호판 중복 검사**
  /// [plateNumber]: 검사할 번호판
  /// 반환값: 중복 여부 (true 또는 false)
  bool isPlateNumberDuplicated(String plateNumber) {
    final allPlates = [
      ...parkingRequests.map((e) => e.plateNumber),
      ...parkingCompleted.map((e) => e.plateNumber),
      ...departureRequests.map((e) => e.plateNumber),
      ...departureCompleted.map((e) => e.plateNumber),
    ];
    return allPlates.contains(plateNumber);
  }

  /// **운전 상태 업데이트**
  /// [plateNumber]: 선택된 차량 번호판
  Future<void> setDrivingPlate(String plateNumber) async {
    try {
      final String fourDigit = plateNumber.substring(plateNumber.length - 4);
      isDrivingPlate = isDrivingPlate == plateNumber ? null : plateNumber;

      await FirebaseFirestore.instance
          .collection('parking_requests')
          .doc(fourDigit)
          .update({'type': isDrivingPlate == null ? '입차 요청' : '입차 중'});

      notifyListeners();
    } catch (e) {
      print('Error updating driving state: $e');
    }
  }

  /// **데이터 이동 (컬렉션 간 전송)**
  /// [fromCollection]: 기존 컬렉션
  /// [toCollection]: 새로운 컬렉션
  /// [plateNumber]: 차량 번호판
  /// [newType]: 새 상태
  Future<void> transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String newType,
  }) async {
    try {
      final String fourDigit = plateNumber.substring(plateNumber.length - 4);

      final docSnapshot = await FirebaseFirestore.instance.collection(fromCollection).doc(fourDigit).get();

      if (docSnapshot.exists) {
        final documentData = docSnapshot.data();

        await FirebaseFirestore.instance.collection(fromCollection).doc(fourDigit).delete();

        await FirebaseFirestore.instance.collection(toCollection).doc(fourDigit).set({
          ...documentData!,
          'type': newType,
        });
      } else {
        print('No document found in $fromCollection with ID: $fourDigit');
      }

      notifyListeners();
    } catch (e) {
      print('Error transferring data: $e');
    }
  }

  /// **입차 완료 처리**
  Future<void> setParkingCompleted(String plateNumber) async {
    await transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      newType: '입차 완료',
    );
  }

  /// **출차 요청 처리**
  Future<void> setDepartureRequested(String plateNumber) async {
    await transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      plateNumber: plateNumber,
      newType: '출차 요청',
    );
  }

  /// **출차 완료 처리**
  Future<void> setDepartureCompleted(String plateNumber) async {
    await transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      newType: '출차 완료',
    );
  }

  /// **입차 요청 추가**
  Future<void> addRequest(String plateNumber) async {
    try {
      final String fourDigit = plateNumber.substring(plateNumber.length - 4);

      // 중복 검사
      if (isPlateNumberDuplicated(plateNumber)) {
        throw Exception('이미 등록된 번호판입니다.');
      }

      await FirebaseFirestore.instance.collection('parking_requests').doc(fourDigit).set({
        'plate_number': plateNumber,
        'type': '입차 요청',
        'request_time': DateTime.now(),
        'location': '미지정',
      });

      notifyListeners();
    } catch (e) {
      print('Error adding request: $e');
    }
  }

  /// **입차 완료 데이터 추가**
  Future<void> addCompleted(String plateNumber, String location) async {
    try {
      final String fourDigit = plateNumber.substring(plateNumber.length - 4);

      // 중복 검사
      if (isPlateNumberDuplicated(plateNumber)) {
        throw Exception('이미 등록된 번호판입니다.');
      }

      await FirebaseFirestore.instance.collection('parking_completed').doc(fourDigit).set({
        'plate_number': plateNumber,
        'type': '입차 완료',
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정',
      });

      notifyListeners();
    } catch (e) {
      print('Error adding completed: $e');
    }
  }
}
