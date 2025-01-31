import 'package:flutter/material.dart';
import '../repositories/plate_repository.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;

  PlateState(this._repository) {
    _initializeSubscriptions();
  }

  final Map<String, List<PlateModel>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  /// Firestore 실시간 데이터 동기화 초기화
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      _repository.getCollectionStream(collectionName).listen((data) {
        _data[collectionName] = data;
        notifyListeners();
      });
    }
  }

  /// 공통 로컬 상태 동기화 로직
  void _syncLocalState(String collection, String id, PlateModel updatedPlate) {
    final collectionData = _data[collection];
    if (collectionData != null) {
      final index = collectionData.indexWhere((plate) => plate.id == id);
      if (index != -1) {
        collectionData[index] = updatedPlate;
        notifyListeners();
      }
    }
  }

  /// 특정 지역에 해당하는 번호판 리스트 반환
  List<PlateModel> getPlatesByArea(String collection, String area) {
    final plates = _data[collection]?.where((request) => request.area == area).toList() ?? [];
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
  Future<bool> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? selectedBy,
    String? adjustmentType, // 🔹 추가된 파라미터
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      await _repository.addOrUpdateDocument(collection, documentId, {
        'plate_number': plateNumber,
        'type': type,
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정',
        'area': area,
        'userName': userName,
        'adjustmentType': adjustmentType, // 🔹 Firestore에 정산 유형 저장
        'isSelected': false,
        'selectedBy': selectedBy,
      });
      return true;
    } catch (e) {
      debugPrint('Error adding request: $e');
      return false;
    }
  }


  /// 데이터 전송 처리
  Future<bool> transferData({
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
          'isSelected': false,
          'selectedBy': null,
        });
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error transferring data: $e');
      return false;
    }
  }

  /// 선택 상태 토글
  Future<void> toggleIsSelected({
    required String collection,
    required String plateNumber,
    required String area,
    required String userName,
  }) async {
    final plateId = '${plateNumber}_$area';

    try {
      final plate = _data[collection]?.firstWhere(
        (p) => p.id == plateId,
        orElse: () => throw Exception('Plate not found'),
      );

      if (plate != null) {
        _validateSelection(plate, userName);

        final newIsSelected = !plate.isSelected;
        await _repository.updatePlateSelection(
          collection,
          plateId,
          newIsSelected,
          selectedBy: newIsSelected ? userName : null,
        );

        final updatedPlate = PlateModel(
          id: plate.id,
          plateNumber: plate.plateNumber,
          type: plate.type,
          requestTime: plate.requestTime,
          location: plate.location,
          area: plate.area,
          userName: plate.userName,
          isSelected: newIsSelected,
          selectedBy: newIsSelected ? userName : null,
        );
        _syncLocalState(collection, plateId, updatedPlate);
      }
    } catch (e) {
      debugPrint('Error toggling isSelected: $e');
    }
  }

  /// 선택 상태 유효성 검사
  void _validateSelection(PlateModel plate, String userName) {
    if (plate.selectedBy != null && plate.selectedBy != userName) {
      debugPrint('Plate is already selected by another user: ${plate.selectedBy}');
      throw Exception('This plate is already selected.');
    }
  }

  /// 선택된 번호판 반환
  PlateModel? getSelectedPlate(String collection, String userName) {
    try {
      return _data[collection]?.firstWhere(
        (plate) => plate.isSelected && plate.selectedBy == userName,
      );
    } catch (e) {
      debugPrint('Error in getSelectedPlate: $e');
      return null;
    }
  }

  /// 상태 전환 메서드들
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

  /// 지역 상태와 동기화
  void syncWithAreaState(String area) {
    debugPrint('PlateState: Syncing with area state: $area');
    notifyListeners();
  }
}
