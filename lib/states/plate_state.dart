import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
              : DateTime.now(),
      location: doc['location'],
    );
  }

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

  String? isDrivingPlate; // 운전 중인 차량 번호를 저장

  List<PlateRequest> get parkingRequests => _data['parking_requests']!;

  List<PlateRequest> get parkingCompleted => _data['parking_completed']!;

  List<PlateRequest> get departureRequests => _data['departure_requests']!;

  List<PlateRequest> get departureCompleted => _data['departure_completed']!;

  PlateState() {
    _initializeSubscriptions();
  }

  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
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
    }
  }

  Future<void> setDrivingPlate(String plateNumber) async {
    if (plateNumber.isEmpty) {
      print('Error: plateNumber is empty');
      return;
    }

    try {
      if (isDrivingPlate == plateNumber) {
        isDrivingPlate = null;

        final query = await FirebaseFirestore.instance
            .collection('parking_requests')
            .where('plate_number', isEqualTo: plateNumber)
            .get();

        if (query.docs.isNotEmpty) {
          final docId = query.docs.first.id;
          await FirebaseFirestore.instance.collection('parking_requests').doc(docId).update({'type': '입차 요청'});
        }
      } else {
        isDrivingPlate = plateNumber;

        final query = await FirebaseFirestore.instance
            .collection('parking_requests')
            .where('plate_number', isEqualTo: plateNumber)
            .get();

        if (query.docs.isNotEmpty) {
          final docId = query.docs.first.id;
          await FirebaseFirestore.instance.collection('parking_requests').doc(docId).update({'type': '입차 중'});
        }
      }

      notifyListeners();
    } catch (e) {
      print('Error updating type: $e');
    }
  }

  Future<void> transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String newType,
  }) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection(fromCollection)
          .where('plate_number', isEqualTo: plateNumber)
          .get();

      if (query.docs.isNotEmpty) {
        final docId = query.docs.first.id;
        final documentData = query.docs.first.data();

        await FirebaseFirestore.instance.collection(fromCollection).doc(docId).delete();
        await FirebaseFirestore.instance.collection(toCollection).add({
          ...documentData,
          'type': newType,
        });
      } else {
        print('No matching document found in $fromCollection for plate: $plateNumber');
      }
    } catch (e) {
      print('Error transferring data from $fromCollection to $toCollection: $e');
    }

    notifyListeners();
  }

  Future<void> setParkingCompleted(String plateNumber) async {
    await transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      newType: '입차 완료',
    );
  }

  Future<void> setDepartureRequested(String plateNumber) async {
    await transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      plateNumber: plateNumber,
      newType: '출차 요청',
    );
  }

  Future<void> setDepartureCompleted(String plateNumber) async {
    await transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      newType: '출차 완료',
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
      await FirebaseFirestore.instance.collection('parking_requests').doc(id).update({'type': newType});
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update request: $e');
    }
  }
}
