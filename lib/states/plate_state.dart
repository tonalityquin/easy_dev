import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/plate_request.dart';
import '../repositories/plate_repository.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;

  PlateState(this._repository) {
    _initializeSubscriptions();
  }

  final Map<String, List<PlateRequest>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  String? isDrivingPlate;

  /// **Firestore 실시간 데이터 동기화 초기화**
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      _repository.getCollectionStream(collectionName).listen((data) {
        _data[collectionName] = data;
        notifyListeners();
      });
    }
  }

  List<PlateRequest> getPlatesByArea(String collection, String area) {
    return _data[collection]!.where((request) => request.area == area).toList();
  }

  bool isPlateNumberDuplicated(String plateNumber, String area) {
    final platesInArea = _data.entries
        .where((entry) => entry.key != 'departure_completed')
        .expand((entry) => entry.value)
        .where((request) => request.area == area)
        .map((request) => request.plateNumber);
    return platesInArea.contains(plateNumber);
  }

  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
  }) async {
    final documentId = '${plateNumber}_$area';

    if (isPlateNumberDuplicated(plateNumber, area)) {
      debugPrint('중복된 번호판: $plateNumber');
      return;
    }

    try {
      await _repository.addOrUpdateDocument(
        collection,
        documentId,
        {
          'plate_number': plateNumber,
          'type': type,
          'request_time': DateTime.now(),
          'location': location.isNotEmpty ? location : '미지정',
          'area': area,
        },
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding data to $collection: $e');
    }
  }

  Future<void> transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String area,
    required String newType,
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      final documentData = await _repository.getDocument(fromCollection, documentId);

      if (documentData != null) {
        await _repository.deleteDocument(fromCollection, documentId);
        await _repository.addOrUpdateDocument(toCollection, documentId, {
          ...documentData,
          'type': newType,
        });

        _data[fromCollection]!.removeWhere((request) => request.id == documentId);
        final updatedRequest = PlateRequest(
          id: documentId,
          plateNumber: documentData['plate_number'],
          type: newType,
          requestTime: (documentData['request_time'] as Timestamp).toDate(),
          location: documentData['location'],
          area: documentData['area'],
        );
        _data[toCollection]!.add(updatedRequest);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error transferring data: $e');
    }
  }

  Future<void> setParkingCompleted(String plateNumber, String area) async {
    await transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '입차 완료',
    );
  }

  Future<void> setDepartureRequested(String plateNumber, String area) async {
    await transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 요청',
    );
  }

  Future<void> setDepartureCompleted(String plateNumber, String area) async {
    await transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 완료',
    );
  }

  void refreshPlateState() {
    notifyListeners();
  }
}
