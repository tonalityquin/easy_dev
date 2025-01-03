import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PlateState extends ChangeNotifier {
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _completed = [];
  List<Map<String, dynamic>> _departureRequests = [];
  List<Map<String, dynamic>> _departureCompleted = [];

  List<Map<String, dynamic>> get requests => _requests;
  List<Map<String, dynamic>> get completed => _completed;
  List<Map<String, dynamic>> get departureRequests => _departureRequests;
  List<Map<String, dynamic>> get departureCompleted => _departureCompleted;

  PlateState() {
    _subscribeToRequests();
    _subscribeToCompleted();
    _subscribeToDepartureRequests();
    _subscribeToDepartureCompleted();
  }

  void _subscribeToRequests() {
    FirebaseFirestore.instance
        .collection('parking_requests')
        .orderBy('request_time', descending: true)
        .snapshots()
        .listen((snapshot) {
      _requests = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      notifyListeners();
    });
  }

  void _subscribeToCompleted() {
    FirebaseFirestore.instance
        .collection('parking_completed')
        .orderBy('request_time', descending: true)
        .snapshots()
        .listen((snapshot) {
      _completed = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      notifyListeners();
    });
  }

  void _subscribeToDepartureRequests() {
    FirebaseFirestore.instance
        .collection('departure_requests')
        .orderBy('request_time', descending: true)
        .snapshots()
        .listen((snapshot) {
      _departureRequests = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      notifyListeners();
    });
  }

  void _subscribeToDepartureCompleted() {
    FirebaseFirestore.instance
        .collection('departure_completed')
        .orderBy('request_time', descending: true)
        .snapshots()
        .listen((snapshot) {
      _departureCompleted = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      notifyListeners();
    });
  }

  Future<void> moveData({
    required String fromCollection,
    required String toCollection,
    required String id,
    required Map<String, dynamic> updates,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(fromCollection).doc(id).get();
      if (snapshot.exists) {
        final data = snapshot.data()!;

        await FirebaseFirestore.instance.collection(toCollection).add({
          ...data,
          ...updates,
        });

        await FirebaseFirestore.instance.collection(fromCollection).doc(id).delete();

        notifyListeners();
      }
    } catch (e) {
      print('Failed to move data from $fromCollection to $toCollection: $e');
    }
  }

  Future<void> addRequest(String plateNumber) async {
    try {
      // Firestore에서 동일한 번호판이 있는지 확인
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

      // 동일한 번호판이 존재하는지 확인
      if (existingRequests.docs.isNotEmpty ||
          existingCompleted.docs.isNotEmpty ||
          existingDepartureRequests.docs.isNotEmpty) {
        print('Failed to add request: Duplicate plate number found');
        throw Exception('동일한 번호판이 이미 존재합니다.');
      }

      // 중복이 없으면 새 요청 추가
      final timestamp = DateTime.now();
      await FirebaseFirestore.instance.collection('parking_requests').add({
        'plate_number': plateNumber,
        'type': '입차 요청',
        'request_time': timestamp,
        'location': '미지정',
      });

      print('Request added successfully');
    } catch (e) {
      print('Failed to add request: $e');
      rethrow; // 오류를 다시 throw하여 UI에서 처리할 수 있도록 전달
    }
  }



  Future<void> addCompleted(String id, String location) async {
    await moveData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      id: id,
      updates: {
        'type': '입차 완료',
        'location': location,
      },
    );
  }

  Future<void> addDepartureRequest(String id) async {
    await moveData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      id: id,
      updates: {
        'type': '출차 요청',
      },
    );
  }

  Future<void> addDepartureCompleted(String id) async {
    await moveData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      id: id,
      updates: {
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
      print('Failed to update request: $e');
    }
  }
}
