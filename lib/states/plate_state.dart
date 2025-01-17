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

  /// Firestore 실시간 데이터 동기화 초기화
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      _repository.getCollectionStream(collectionName).listen((data) {
        _data[collectionName] = data;
        notifyListeners();
      });
    }
  }

  /// 특정 지역에 해당하는 번호판 리스트 반환
  List<PlateRequest> getPlatesByArea(String collection, String area) {
    final plates = _data[collection]!.where((request) => request.area == area).toList();
    debugPrint('Filtered Plates for $collection in $area: $plates');
    return plates;
  }

  /// 번호판 중복 여부 확인
  bool isPlateNumberDuplicated(String plateNumber, String area) {
    final platesInArea = _data.entries
        .where((entry) => entry.key != 'departure_completed') // 'departure_completed' 제외
        .expand((entry) => entry.value) // 각 컬렉션 데이터 평탄화
        .where((request) => request.area == area) // 특정 지역 데이터 필터링
        .map((request) => request.plateNumber); // 번호판만 추출
    return platesInArea.contains(plateNumber); // 중복 여부 확인
  }

  /// 번호판 추가 요청 처리
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
  }) async {
    if (isPlateNumberDuplicated(plateNumber, area)) {
      debugPrint('중복된 번호판: $plateNumber');
      return;
    }

    try {
      await _repository.addRequestOrCompleted(
        collection: collection,
        plateNumber: plateNumber,
        location: location,
        area: area,
        type: type,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('Error adding request or completed: $e');
    }
  }

  /// 데이터 전송 처리
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
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error transferring data: $e');
    }
  }

  /// 입차 완료 처리
  Future<void> setParkingCompleted(String plateNumber, String area) async {
    await transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '입차 완료',
    );
  }

  /// 출차 요청 처리
  Future<void> setDepartureRequested(String plateNumber, String area) async {
    await transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 요청',
    );
  }

  /// 출차 완료 처리
  Future<void> setDepartureCompleted(String plateNumber, String area) async {
    await transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 완료',
    );
  }

  /// 모든 데이터 삭제
  Future<void> deleteAllData() async {
    try {
      await _repository.deleteAllData();
      notifyListeners(); // 상태 갱신 후 UI에 반영
    } catch (e) {
      debugPrint('Error deleting all data: $e');
    }
  }

  /// 특정 지역에서 사용 가능한 주차 구역 가져오기
  Future<List<String>> getAvailableLocations(String area) async {
    try {
      final locations = await _repository.getAvailableLocations(area);
      debugPrint('Available locations in $area: $locations');
      return locations;
    } catch (e) {
      debugPrint('Error fetching available locations: $e');
      return [];
    }
  }

  /// 상태 갱신
  void refreshPlateState() {
    notifyListeners();
  }
}
