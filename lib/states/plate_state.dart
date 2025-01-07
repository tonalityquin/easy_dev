import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Plate 데이터 모델 정의
class PlateRequest {
  final String id;
  final String plateNumber;
  final String type;
  final DateTime requestTime;
  final String location;

  PlateRequest({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.requestTime,
    required this.location,
  });

  /// Firestore 문서를 PlateRequest 객체로 변환
  factory PlateRequest.fromDocument(QueryDocumentSnapshot doc) {
    final dynamic timestamp = doc['request_time'];
    return PlateRequest(
      id: doc.id,
      plateNumber: doc['plate_number'],
      type: doc['type'],
      requestTime: (timestamp is Timestamp)
          ? timestamp.toDate()
          : (timestamp is DateTime)
          ? timestamp
          : DateTime.now(), // DateTime 형식일 경우 그대로 사용, null 또는 잘못된 값은 현재 시간으로 대체
      location: doc['location'],
    );
  }


  /// PlateRequest 객체를 Firestore에 저장할 데이터로 변환
  Map<String, dynamic> toMap() {
    return {
      'plate_number': plateNumber,
      'type': type,
      'request_time': requestTime,
      'location': location,
    };
  }
}

class PlateState extends ChangeNotifier {
  final Map<String, List<PlateRequest>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  List<PlateRequest> get parkingRequests => _data['parking_requests']!;
  List<PlateRequest> get parkingCompleted => _data['parking_completed']!;
  List<PlateRequest> get departureRequests => _data['departure_requests']!;
  List<PlateRequest> get departureCompleted => _data['departure_completed']!;

  PlateState() {
    _initializeSubscriptions();
  }

  /// Firestore 구독 초기화
  void _initializeSubscriptions() {
    _data.keys.forEach((collectionName) {
      FirebaseFirestore.instance
          .collection(collectionName)
          .orderBy('request_time', descending: true)
          .snapshots()
          .listen((snapshot) {
        _data[collectionName]!.clear();
        _data[collectionName]!.addAll(
          snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList(),
        );
        notifyListeners();
      });
    });
  }

  /// 데이터 이동 로직
  Future<void> transferData({
    required String fromCollection,
    required String toCollection,
    required String id,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(fromCollection).doc(id).get();
      if (!snapshot.exists) throw Exception('Document not found in $fromCollection');

      final data = snapshot.data()!;
      final updatedData = {...data, ...?additionalData};
      await FirebaseFirestore.instance.collection(toCollection).add(updatedData);
      await FirebaseFirestore.instance.collection(fromCollection).doc(id).delete();

      notifyListeners();
    } catch (e) {
      throw Exception('Failed to transfer data: $e');
    }
  }

  Future<void> addCompleted(String id, String location) async {
    await transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      id: id,
      additionalData: {'type': '입차 완료', 'location': location},
    );
  }

  Future<void> addDepartureRequest(String id) async {
    await transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      id: id,
      additionalData: {'type': '출차 요청'},
    );
  }

  Future<void> addDepartureCompleted(String id) async {
    await transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      id: id,
      additionalData: {'type': '출차 완료'},
    );
  }

  Future<void> addRequest(String plateNumber) async {
    try {
      for (String collectionName in _data.keys) {
        final query = await FirebaseFirestore.instance
            .collection(collectionName)
            .where('plate_number', isEqualTo: plateNumber)
            .get();
        if (query.docs.isNotEmpty) throw Exception('Plate number already exists in $collectionName');
      }

      await FirebaseFirestore.instance.collection('parking_requests').add({
        'plate_number': plateNumber,
        'type': '입차 요청',
        'request_time': DateTime.now(),
        'location': '미지정',
      });
    } catch (e) {
      throw Exception('Failed to add request: $e');
    }
  }

  Future<void> updateRequest(String id, String newType) async {
    try {
      await FirebaseFirestore.instance
          .collection('parking_requests')
          .doc(id)
          .update({'type': newType});
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update request: $e');
    }
  }
}
