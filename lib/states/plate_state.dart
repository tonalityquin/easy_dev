import 'package:flutter/material.dart';
import '../repositories/plate/plate_repository.dart';
import '../models/plate_model.dart';

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
  String? _searchQuery;

  String get searchQuery => _searchQuery ?? "";

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearPlateSearchQuery() {
    _searchQuery = null;
    notifyListeners();
  }

  List<PlateModel> getPlatesByArea(String collection, String area) {
    final plates = _data[collection]?.where((request) => request.area == area).toList() ?? [];
    if (_searchQuery != null && _searchQuery!.length == 4) {
      return plates.where((plate) {
        final last4Digits = plate.plateNumber.length >= 4
            ? plate.plateNumber.substring(plate.plateNumber.length - 4)
            : plate.plateNumber;
        return last4Digits == _searchQuery;
      }).toList();
    }
    return plates;
  }

  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      _repository.getCollectionStream(collectionName).listen((data) {
        _data[collectionName] = data;
        notifyListeners();
      });
    }
  }

  List<PlateModel> getFilteredPlates(String collection, String area, String? searchDigits) {
    final plates = getPlatesByArea(collection, area);
    if (searchDigits == null || searchDigits.isEmpty) {
      return plates;
    }
    return plates.where((plate) {
      // 🔹 번호판의 마지막 4자리를 추출
      final last4Digits =
          plate.plateNumber.length >= 4 ? plate.plateNumber.substring(plate.plateNumber.length - 4) : plate.plateNumber;
      return last4Digits == searchDigits;
    }).toList();
  }

  List<PlateModel> filterByParkingArea(String collection, String area, String parkingLocation) {
    debugPrint("🚀 filterByParkingArea() 호출됨: 지역 = $area, 주차 구역 = $parkingLocation");
    List<PlateModel> plates = _data[collection]?.where((plate) => plate.area == area).toList() ?? [];
    debugPrint("📌 지역 필터링 후 plate 개수: ${plates.length}");
    plates = plates.where((plate) => plate.location == parkingLocation).toList();
    debugPrint("📌 주차 구역 필터링 후 plate 개수: ${plates.length}");
    return plates;
  }

  void clearLocationSearchQuery() {
    debugPrint("🔄 주차 구역 검색 초기화 호출됨");
    _initializeSubscriptions();
    notifyListeners();
  }

  bool isPlateNumberDuplicated(String plateNumber, String area) {
    final platesInArea = _data.entries
        .where((entry) => entry.key != 'departure_completed')
        .expand((entry) => entry.value)
        .where((request) => request.area == area)
        .map((request) => request.plateNumber);
    return platesInArea.contains(plateNumber);
  }

  Future<bool> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? selectedBy,
    String? adjustmentType,
    List<String>? statusList,
  }) async {
    final documentId = '${plateNumber}_$area';
    try {
      int basicStandard = 0;
      int basicAmount = 0;
      int addStandard = 0;
      int addAmount = 0;
      if (adjustmentType != null) {
        final adjustmentData = await _repository.getDocument('adjustments', adjustmentType);
        if (adjustmentData != null) {
          basicStandard = adjustmentData.basicStandard ?? 0;
          basicAmount = adjustmentData.basicAmount ?? 0;
          addStandard = adjustmentData.addStandard ?? 0;
          addAmount = adjustmentData.addAmount ?? 0;
        } else {
          debugPrint('⚠ Firestore에서 adjustmentType=$adjustmentType 데이터를 찾을 수 없음');
        }
      }
      await _repository.addOrUpdateDocument(collection, documentId, {
        'plate_number': plateNumber,
        'type': type,
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정',
        'area': area,
        'userName': userName,
        'adjustmentType': adjustmentType,
        'statusList': statusList ?? [],
        'isSelected': false,
        'selectedBy': selectedBy,
        'basicStandard': basicStandard,
        'basicAmount': basicAmount,
        'addStandard': addStandard,
        'addAmount': addAmount,
      });
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error adding request: $e');
      return false;
    }
  }

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
        final updatedLocation = (toCollection == 'parking_requests') ? "미지정" : documentData.location;
        await _repository.addOrUpdateDocument(toCollection, documentId, {
          ...documentData.toMap(),
          'type': newType,
          'location': updatedLocation,
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

  Future<void> toggleIsSelected({
    required String collection,
    required String plateNumber,
    required String area,
    required String userName,
    required void Function(String) onError,
  }) async {
    final plateId = '${plateNumber}_$area';
    try {
      final plateList = _data[collection];
      if (plateList == null) throw Exception('🚨 Collection not found');
      final index = plateList.indexWhere((p) => p.id == plateId);
      if (index == -1) throw Exception('🚨 Plate not found');
      final plate = plateList[index];
      final newIsSelected = !plate.isSelected;
      final newSelectedBy = newIsSelected ? userName : null;
      await _repository.updatePlateSelection(
        collection,
        plateId,
        newIsSelected,
        selectedBy: newSelectedBy,
      );
      _data[collection]![index] = PlateModel(
        id: plate.id,
        plateNumber: plate.plateNumber,
        type: plate.type,
        requestTime: plate.requestTime,
        location: plate.location,
        area: plate.area,
        userName: plate.userName,
        isSelected: newIsSelected,
        selectedBy: newSelectedBy,
        adjustmentType: plate.adjustmentType,
        statusList: plate.statusList,
        basicStandard: plate.basicStandard,
        basicAmount: plate.basicAmount,
        addStandard: plate.addStandard,
        addAmount: plate.addAmount,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error toggling isSelected: $e');
      onError('🚨 번호판 선택 상태 변경 실패: $e');
    }
  }

  PlateModel? getSelectedPlate(String collection, String userName) {
    final plates = _data[collection];
    if (plates == null || plates.isEmpty) {
      return null;
    }
    return plates.firstWhere(
      (plate) => plate.isSelected && plate.selectedBy == userName,
      orElse: () => PlateModel(
        id: '',
        plateNumber: '',
        type: '',
        requestTime: DateTime.now(),
        location: '',
        area: '',
        userName: '',
        isSelected: false,
        statusList: [],
      ),
    );
  }

  PlateModel? _findPlate(String collection, String plateNumber) {
    try {
      return _data[collection]?.firstWhere(
        (plate) => plate.plateNumber == plateNumber,
      );
    } catch (e) {
      debugPrint("🚨 Error in _findPlate: $e");
      return null;
    }
  }

  Future<void> deletePlateFromParkingRequest(String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';
    try {
      await _repository.deleteDocument('parking_requests', documentId);
      _data['parking_requests']?.removeWhere((plate) => plate.plateNumber == plateNumber);
      notifyListeners();
      debugPrint("✅ 번호판 삭제 완료: $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패: $e");
    }
  }

  Future<void> deletePlateFromParkingCompleted(String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';
    try {
      await _repository.deleteDocument('parking_completed', documentId);
      _data['parking_completed']?.removeWhere((plate) => plate.plateNumber == plateNumber);
      notifyListeners(); // 🔄 UI 갱신
      debugPrint("✅ 번호판 삭제 완료 (입차 완료 컬렉션): $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 (입차 완료 컬렉션): $e");
    }
  }

  void goBackToParkingRequest(String plateNumber, String? newLocation) {
    for (final collection in _data.keys) {
      final plates = _data[collection];
      if (plates != null) {
        final index = plates.indexWhere((plate) => plate.plateNumber == plateNumber);
        if (index != -1) {
          final oldPlate = plates[index];
          final updatedLocation = (newLocation == null || newLocation.trim().isEmpty) ? "미지정" : newLocation;
          plates.removeAt(index);
          final updatedPlate = PlateModel(
            id: oldPlate.id,
            plateNumber: oldPlate.plateNumber,
            type: oldPlate.type,
            requestTime: oldPlate.requestTime,
            location: updatedLocation,
            area: oldPlate.area,
            userName: oldPlate.userName,
            isSelected: oldPlate.isSelected,
            selectedBy: oldPlate.selectedBy,
            adjustmentType: oldPlate.adjustmentType,
            statusList: oldPlate.statusList,
            basicStandard: oldPlate.basicStandard,
            basicAmount: oldPlate.basicAmount,
            addStandard: oldPlate.addStandard,
            addAmount: oldPlate.addAmount,
          );
          plates.insert(index, updatedPlate);
          notifyListeners();
          return;
        }
      }
    }
  }

  Future<void> deletePlateFromDepartureRequest(String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';
    try {
      await _repository.deleteDocument('departure_requests', documentId);
      _data['departure_requests']?.removeWhere((plate) => plate.plateNumber == plateNumber);
      notifyListeners(); // 🔄 UI 갱신
      debugPrint("✅ 번호판 삭제 완료 (입차 완료 컬렉션): $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 (입차 완료 컬렉션): $e");
    }
  }

  Future<void> movePlateToCompleted(String plateNumber, String location) async {
    final selectedPlate = _findPlate('parking_requests', plateNumber);
    if (selectedPlate != null) {
      final updatedPlate = PlateModel(
        id: selectedPlate.id,
        plateNumber: selectedPlate.plateNumber,
        type: '입차 완료',
        requestTime: selectedPlate.requestTime,
        location: location,
        area: selectedPlate.area,
        userName: selectedPlate.userName,
        isSelected: false,
        selectedBy: null,
        adjustmentType: selectedPlate.adjustmentType,
        statusList: selectedPlate.statusList,
        basicStandard: selectedPlate.basicStandard,
        basicAmount: selectedPlate.basicAmount,
        addStandard: selectedPlate.addStandard,
        addAmount: selectedPlate.addAmount,
      );
      final documentId = '${plateNumber}_${selectedPlate.area}';
      try {
        await _repository.deleteDocument('parking_requests', documentId);
        await _repository.addOrUpdateDocument('parking_completed', documentId, {
          'plate_number': updatedPlate.plateNumber,
          'type': updatedPlate.type,
          'request_time': updatedPlate.requestTime,
          'location': updatedPlate.location,
          'area': updatedPlate.area,
          'userName': updatedPlate.userName,
          'adjustmentType': updatedPlate.adjustmentType,
          'statusList': updatedPlate.statusList,
          'isSelected': updatedPlate.isSelected,
          'selectedBy': updatedPlate.selectedBy,
          'basicStandard': updatedPlate.basicStandard,
          'basicAmount': updatedPlate.basicAmount,
          'addStandard': updatedPlate.addStandard,
          'addAmount': updatedPlate.addAmount,
        });
        _data['parking_requests']?.removeWhere((plate) => plate.plateNumber == plateNumber);
        _data['parking_completed']?.add(updatedPlate);
        notifyListeners();
      } catch (e) {
        debugPrint('🚨 Firestore 데이터 이동 실패: $e');
      }
    }
  }

  Future<void> updatePlateStatus({
    required String plateNumber,
    required String area,
    required String fromCollection,
    required String toCollection,
    required String newType,
  }) async {
    await transferData(
      fromCollection: fromCollection,
      toCollection: toCollection,
      plateNumber: plateNumber,
      area: area,
      newType: newType,
    );
  }

  Future<void> setParkingCompleted(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      newType: '입차 완료',
    );
  }

  Future<void> setDepartureRequested(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      newType: '출차 요청',
    );
    notifyListeners();
  }

  Future<void> setDepartureCompleted(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      newType: '출차 완료',
    );
  }

  Future<List<String>> getAvailableLocations(String area) async {
    return await _repository.getAvailableLocations(area);
  }

  void syncWithAreaState(String area) {
    notifyListeners();
  }
}
