import 'package:flutter/foundation.dart';
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

  /// 🔍 특정 지역의 plate 데이터를 가져오는 함수
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

  /// 🔹 Plate 개수를 출력하는 함수
  void PlateCounts(String area) {
    final int parkingRequests = getPlatesByArea('parking_requests', area).length;
    final int parkingCompleted = getPlatesByArea('parking_completed', area).length;
    final int departureRequests = getPlatesByArea('departure_requests', area).length;
    final int departureCompleted = getPlatesByArea('departure_completed', area).length;

    print('📌 Selected Area: $area');
    print('🅿️ Parking Requests: $parkingRequests');
    print('✅ Parking Completed: $parkingCompleted');
    print('🚗 Departure Requests: $departureRequests');
    print('🏁 Departure Completed: $departureCompleted');
  }

  /// 🔄 Firestore 데이터 변경 감지 및 개수 출력 (불필요한 중복 호출 방지)
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      _repository.getCollectionStream(collectionName).listen((data) {
        if (!listEquals(_data[collectionName], data)) {
          // 🔹 중복 데이터 감지
          _data[collectionName] = data;
          notifyListeners();
          if (data.isNotEmpty) {
            PlateCounts(data.first.area);
          }
        }
      });
    }
  }

  /// ✅ 특정 plate의 선택 상태를 토글하는 함수
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

  /// 🔍 특정 유저가 선택한 plate 가져오기
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

  void syncWithAreaState(String area) {
    print("🔄 지역 동기화 실행됨: $area");
    PlateCounts(area); // 🔹 지역 변경 시 개수 즉시 출력
  }
}
