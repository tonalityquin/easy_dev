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

  /// 특정 지역에 해당하는 번호판 리스트 반환
  List<PlateModel> getPlatesByArea(String collection, String area) {
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
    required String userName,
    String? selectedBy, // 선택 유저 추가
  }) async {
    final documentId = '${plateNumber}_$area';

    await _repository.addOrUpdateDocument(collection, documentId, {
      'plate_number': plateNumber,
      'type': type,
      'request_time': DateTime.now(),
      'location': location.isNotEmpty ? location : '미지정',
      'area': area,
      'userName': userName,
      'isSelected': false,
      'selectedBy': selectedBy, // 선택 유저 반영
    });
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
          'isSelected': false, // 선택 상태 초기화
          'selectedBy': null, // 필요 시 유지하거나 초기화
        });
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error transferring data: $e');
    }
  }


  /// 선택 상태 토글
  Future<void> toggleIsSelected({
    required String collection,
    required String plateNumber,
    required String area,
    required String userName, // 현재 유저 이름 추가
  }) async {
    final plateId = '${plateNumber}_$area';
    final plate = _data[collection]?.firstWhere(
          (p) => p.id == plateId,
      orElse: () => PlateModel(
        id: plateId,
        plateNumber: plateNumber,
        type: '', // 기본값
        requestTime: DateTime.now(),
        location: '',
        area: area,
        userName: '',
        isSelected: false,
        selectedBy: null, // 기본값
      ),
    );

    if (plate != null) {
      // 이미 선택된 번호판에 대해 다른 유저가 선택을 시도하면 안됨
      if (plate.selectedBy != null && plate.selectedBy != userName) {
        debugPrint('Plate is already selected by another user: ${plate.selectedBy}');
        return; // 다른 유저가 선택한 경우 작업 차단
      }

      final newIsSelected = !plate.isSelected;

      // Firestore 업데이트
      await _repository.updatePlateSelection(
        collection,
        plateId,
        newIsSelected,
        selectedBy: newIsSelected ? userName : null, // 선택 유저 업데이트
      );

      // 로컬 상태 업데이트
      final index = _data[collection]?.indexOf(plate);
      if (index != null && index >= 0) {
        _data[collection]?[index] = PlateModel(
          id: plate.id,
          plateNumber: plate.plateNumber,
          type: plate.type,
          requestTime: plate.requestTime,
          location: plate.location,
          area: plate.area,
          userName: plate.userName,
          isSelected: newIsSelected,
          selectedBy: newIsSelected ? userName : null, // 선택 유저 업데이트
        );
        notifyListeners();
      }
    }
  }





  /// 선택된 번호판 반환
  PlateModel? getSelectedPlate(String collection, String userName) {
    final collectionData = _data[collection];

    // 데이터가 없거나 비어 있으면 null 반환
    if (collectionData == null || collectionData.isEmpty) {
      return null;
    }

    // 현재 유저가 선택한 번호판만 반환
    try {
      return collectionData.firstWhere(
            (plate) => plate.isSelected && plate.selectedBy == userName,
        orElse: () => PlateModel( // 기본값 반환
          id: '',
          plateNumber: '',
          type: '',
          requestTime: DateTime.now(),
          location: '',
          area: '',
          userName: '',
          isSelected: false,
          selectedBy: null,
        ),
      );
    } catch (e) {
      debugPrint('Error in getSelectedPlate: $e');
      return null;
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

  /// 번호판 선택 상태 업데이트
  Future<void> updateIsSelected({
    required String collection,
    required String id,
    required bool isSelected,
    required String? selectedBy, // 선택한 유저 추가
  }) async {
    try {
      // Firestore 상태 업데이트
      await _repository.updatePlateSelection(collection, id, isSelected, selectedBy: selectedBy);

      // 로컬 상태 동기화
      final collectionData = _data[collection];
      if (collectionData != null) {
        final index = collectionData.indexWhere((plate) => plate.id == id);
        if (index != -1) {
          collectionData[index] = PlateModel(
            id: collectionData[index].id,
            plateNumber: collectionData[index].plateNumber,
            type: collectionData[index].type,
            requestTime: collectionData[index].requestTime,
            location: collectionData[index].location,
            area: collectionData[index].area,
            userName: collectionData[index].userName,
            isSelected: isSelected,
            selectedBy: selectedBy, // 선택 유저 반영
          );
          notifyListeners(); // UI 상태 갱신
        }
      }
    } catch (e) {
      debugPrint('Error updating isSelected: $e');
    }
  }


  /// 상태 갱신
  void refreshPlateState() {
    notifyListeners();
  }
}
