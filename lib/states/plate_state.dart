import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
      location: doc['location'],
      area: doc['area'],
    );
  }

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

/// **PlateState 클래스**
/// - 차량 번호판 데이터 상태 관리
/// - Firestore와 실시간 데이터 동기화
class PlateState extends ChangeNotifier {
  final Map<String, List<PlateRequest>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  String? isDrivingPlate;

  PlateState() {
    _initializeSubscriptions();
  }

  /// **Firestore 실시간 데이터 동기화 초기화**
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      FirebaseFirestore.instance.collection(collectionName).snapshots().listen((snapshot) {
        _data[collectionName] = snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList();
        notifyListeners();
      });
    }
  }

  /// **특정 지역의 데이터 반환**
  List<PlateRequest> getPlatesByArea(String collection, String area) {
    return _data[collection]!.where((request) => request.area == area).toList();
  }

  bool isPlateNumberDuplicated(String plateNumber, String area) {
    final platesInArea = _data.entries
        .where((entry) => entry.key != 'departure_completed') // departure_completed 제외
        .expand((entry) => entry.value) // 각 컬렉션 데이터 평탄화
        .where((request) => request.area == area) // 특정 지역 데이터 필터링
        .map((request) => request.plateNumber); // 번호판만 추출
    return platesInArea.contains(plateNumber); // 중복 여부 확인
  }

  /// **Firestore에 데이터 추가**
  Future<void> updateFirestore({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await FirebaseFirestore.instance.collection(collection).doc(documentId).set(data);
    } catch (e) {
      debugPrint('Error updating Firestore: $e');
    }
  }

  /// **요청 및 완료 데이터 추가**
  /// - 요청(`parking_requests`) 또는 완료(`parking_completed`) 데이터를 추가.
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
      await updateFirestore(
        collection: collection,
        documentId: documentId,
        data: {
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

  /// **데이터 이동**
  Future<void> transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String area,
    required String newType,
  }) async {
    try {
      final String documentId = '${plateNumber}_$area';

      // Firestore에서 기존 문서 가져오기
      final docSnapshot = await FirebaseFirestore.instance.collection(fromCollection).doc(documentId).get();

      if (docSnapshot.exists) {
        final documentData = docSnapshot.data();

        // Firestore에서 기존 문서 삭제
        await FirebaseFirestore.instance.collection(fromCollection).doc(documentId).delete();

        // Firestore에 새 문서 추가
        await FirebaseFirestore.instance.collection(toCollection).doc(documentId).set({
          ...documentData!,
          'type': newType,
        });

        // 로컬 상태 업데이트
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
