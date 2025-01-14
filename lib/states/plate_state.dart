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

  /// **copyWith 메서드**
  /// - 특정 필드를 변경한 새 PlateRequest 객체 생성
  PlateRequest copyWith({
    String? id,
    String? plateNumber,
    String? type,
    DateTime? requestTime,
    String? location,
    String? area,
  }) {
    return PlateRequest(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      type: type ?? this.type,
      requestTime: requestTime ?? this.requestTime,
      location: location ?? this.location,
      area: area ?? this.area,
    );
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
        final newData = snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList();
        final seenIds = <String>{};

        // 중복 제거 후 데이터 추가
        _data[collectionName]!.clear();
        for (final request in newData) {
          if (!seenIds.contains(request.id)) {
            _data[collectionName]!.add(request);
            seenIds.add(request.id);
          }
        }

        notifyListeners(); // 상태 변경 알림
      });
    }
  }

  /// **특정 지역에 해당하는 데이터 반환**
  List<PlateRequest> getPlatesByArea(String collection, String area) {
    return _data[collection]!.where((request) => request.area == area).toList();
  }

  bool isPlateNumberDuplicated(String plateNumber, String area) {
    // 특정 지역의 데이터를 필터링
    final platesInArea = [
      ...parkingRequests.where((e) => e.area == area).map((e) => e.plateNumber),
      ...parkingCompleted.where((e) => e.area == area).map((e) => e.plateNumber),
      ...departureRequests.where((e) => e.area == area).map((e) => e.plateNumber),
    ];

    return platesInArea.contains(plateNumber); // 지역 내 중복 여부 확인
  }

  Future<void> setDrivingPlate(String plateNumber, String area) async {
    try {
      final String documentId = '${plateNumber}_$area';

      await FirebaseFirestore.instance
          .collection('parking_requests')
          .doc(documentId)
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
    required String area,
    required String newType,
  }) async {
    try {
      final String documentId = '${plateNumber}_$area'; // DB와 동일한 문서 ID 생성
      print('Transferring document: $documentId from $fromCollection to $toCollection');

      // Firestore에서 기존 문서 가져오기
      final docSnapshot = await FirebaseFirestore.instance.collection(fromCollection).doc(documentId).get();

      if (docSnapshot.exists) {
        final documentData = docSnapshot.data(); // 삭제 전에 데이터 참조
        print('Document data found: $documentData');

        // Firestore에서 기존 문서 삭제
        await FirebaseFirestore.instance.collection(fromCollection).doc(documentId).delete();
        print('Document deleted from $fromCollection: $documentId');

        // Firestore에 새 문서 추가
        await FirebaseFirestore.instance.collection(toCollection).doc(documentId).set({
          ...documentData!,
          'type': newType,
        });
        print('Document added to $toCollection: $documentId');

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
        print('Local state updated: $documentId');
      } else {
        print('No document found in $fromCollection with ID: $documentId');
      }
    } catch (e) {
      print('Error transferring data: $e');
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

  Future<void> addRequest(String plateNumber, String location, String area) async {
    try {
      // plateNumber와 area를 조합하여 문서 ID 생성
      final String documentId = '${plateNumber}_$area';

      // 특정 지역 내 중복 검증
      if (isPlateNumberDuplicated(plateNumber, area)) {
        throw Exception('동일 지역에 이미 등록된 번호판입니다.');
      }

      await FirebaseFirestore.instance.collection('parking_requests').doc(documentId).set({
        'plate_number': plateNumber,
        'type': '입차 요청',
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정',
        'area': area, // 지역 정보 저장
      });

      notifyListeners();
    } catch (e) {
      print('Error adding request: $e');
    }
  }

  Future<void> addCompleted(String plateNumber, String location, String area) async {
    try {
      // plateNumber와 area를 조합하여 문서 ID 생성
      final String documentId = '${plateNumber}_$area';

      // 특정 지역 내 중복 검증
      if (isPlateNumberDuplicated(plateNumber, area)) {
        throw Exception('동일 지역에 이미 등록된 번호판입니다.');
      }

      await FirebaseFirestore.instance.collection('parking_completed').doc(documentId).set({
        'plate_number': plateNumber,
        'type': '입차 완료',
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정',
        'area': area,
      });

      notifyListeners();
    } catch (e) {
      print('Error adding completed: $e');
    }
  }

  /// PlateState의 상태를 갱신하고 알림을 보냅니다.
  void refreshPlateState() {
    notifyListeners();
  }
}
