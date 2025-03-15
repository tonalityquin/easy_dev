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

  void syncWithAreaState(String area) {
    notifyListeners();
  }
}
