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

  String? isDrivingPlate;

  List<PlateRequest> get parkingRequests => _data['parking_requests']!;

  List<PlateRequest> get parkingCompleted => _data['parking_completed']!;

  List<PlateRequest> get departureRequests => _data['departure_requests']!;

  List<PlateRequest> get departureCompleted => _data['departure_completed']!;

  PlateState() {
    _initializeSubscriptions();
  }

  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      FirebaseFirestore.instance.collection(collectionName).snapshots().listen((snapshot) {
        _data[collectionName]!.clear();
        _data[collectionName]!.addAll(
          snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList(),
        );
        notifyListeners();
      });
    }
  }

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
      final String fourDigit = plateNumber.substring(plateNumber.length - 4);

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

  Future<void> addCompleted(String plateNumber, String location) async {
    try {
      final String fourDigit = plateNumber.substring(plateNumber.length - 4);

      await FirebaseFirestore.instance.collection('parking_completed').doc(fourDigit).set({
        'plate_number': plateNumber,
        'type': '입차 요청',
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정', // location 값 사용
      });

      notifyListeners();
    } catch (e) {
      print('Error adding completed: $e');
    }
  }
}
