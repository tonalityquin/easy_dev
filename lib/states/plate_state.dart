import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PlateState extends ChangeNotifier {
  final List<Map<String, dynamic>> _requests = [];
  final List<Map<String, dynamic>> _completed = [];
  final List<Map<String, dynamic>> _departureRequests = [];
  final List<Map<String, dynamic>> _departureCompleted = [];

  List<Map<String, dynamic>> get requests => _requests;
  List<Map<String, dynamic>> get completed => _completed;
  List<Map<String, dynamic>> get departureRequests => _departureRequests;
  List<Map<String, dynamic>> get departureCompleted => _departureCompleted;

  void _subscribeToCollection(String collectionName, List<Map<String, dynamic>> targetList) {
    FirebaseFirestore.instance
        .collection(collectionName)
        .orderBy('request_time', descending: true)
        .snapshots()
        .listen((snapshot) {
      targetList.clear();
      targetList.addAll(
        snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(),
      );
      notifyListeners();
    });
  }

  // 생성자에서 모든 구독 초기화
  PlateState() {
    _subscribeToCollection('parking_requests', _requests);
    _subscribeToCollection('parking_completed', _completed);
    _subscribeToCollection('departure_requests', _departureRequests);
    _subscribeToCollection('departure_completed', _departureCompleted);
  }

  // 데이터를 이동하는 공통 메서드
  Future<void> transferData({
    required String fromCollection,
    required String toCollection,
    required String id,
    Map<String, dynamic>? additionalData, // 선택적으로 데이터를 추가
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(fromCollection).doc(id).get();
      if (!snapshot.exists) {
        throw Exception('Document with id $id not found in $fromCollection');
      }

      final data = snapshot.data()!;
      await FirebaseFirestore.instance.collection(toCollection).add({
        ...data,
        ...?additionalData, // 추가 데이터 병합
      });

      await FirebaseFirestore.instance.collection(fromCollection).doc(id).delete();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to transfer data from $fromCollection to $toCollection: $e');
    }
  }

  Future<void> addCompleted(String id, String location) async {
    await transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      id: id,
      additionalData: {
        'type': '입차 완료',
        'location': location,
      },
    );
  }

  Future<void> addDepartureRequest(String id) async {
    await transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      id: id,
      additionalData: {
        'type': '출차 요청',
      },
    );
  }

  Future<void> addDepartureCompleted(String id) async {
    await transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      id: id,
      additionalData: {
        'type': '출차 완료',
      },
    );
  }

  Future<void> updateRequest(String id, String newType) async {
    try {
      await FirebaseFirestore.instance.collection('parking_requests').doc(id).update({
        'type': newType,
      });
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update request: $e');
    }
  }

  Future<void> addRequest(String plateNumber) async {
    try {
      final existingRequests = await FirebaseFirestore.instance
          .collection('parking_requests')
          .where('plate_number', isEqualTo: plateNumber)
          .get();

      final existingCompleted = await FirebaseFirestore.instance
          .collection('parking_completed')
          .where('plate_number', isEqualTo: plateNumber)
          .get();

      final existingDepartureRequests = await FirebaseFirestore.instance
          .collection('departure_requests')
          .where('plate_number', isEqualTo: plateNumber)
          .get();

      if (existingRequests.docs.isNotEmpty ||
          existingCompleted.docs.isNotEmpty ||
          existingDepartureRequests.docs.isNotEmpty) {
        throw Exception('동일한 번호판이 이미 존재합니다.');
      }

      final timestamp = DateTime.now();
      await FirebaseFirestore.instance.collection('parking_requests').add({
        'plate_number': plateNumber,
        'type': '입차 요청',
        'request_time': timestamp,
        'location': '미지정',
      });
    } catch (e) {
      throw Exception('Failed to add request: $e');
    }
  }
}
