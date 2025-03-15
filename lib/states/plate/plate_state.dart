import 'package:flutter/material.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';

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

  void syncWithAreaState(String area) {
    notifyListeners();
  }
}
