import 'dart:async';
import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';

class FilterPlate extends ChangeNotifier {
  final PlateRepository _repository;
  final String currentArea;

  FilterPlate(this._repository, this.currentArea) {
    debugPrint("✅ FilterPlate created with area: $currentArea");
    _initializeData();
  }

  final Map<PlateType, List<PlateModel>> _data = {
    for (var type in PlateType.values) type: [],
  };

  final Map<PlateType, StreamSubscription<List<PlateModel>>> _subscriptions = {};

  String? _searchQuery;
  String? _locationQuery;

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  /// 🔁 지역 기반으로 PlateType별 스트림 구독
  void _initializeData() {
    for (final plateType in PlateType.values) {
      _subscriptions[plateType]?.cancel();

      final stream = _repository.getPlatesByTypeAndArea(plateType, currentArea);

      _subscriptions[plateType] = stream.listen((data) {
        _data[plateType] = data;
        notifyListeners();
      }, onError: (error) {
        debugPrint("🔥 plate stream error: $error");
      });
    }
  }

  void setPlateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearPlateSearchQuery() {
    _searchQuery = null;
    notifyListeners();
  }

  List<PlateModel> filterPlatesByQuery(List<PlateModel> plates) {
    if (_searchQuery != null && _searchQuery!.length == 4) {
      return plates.where((plate) => plate.plateFourDigit == _searchQuery).toList();
    }
    return plates;
  }

  Future<List<PlateModel>> fetchPlatesBySearchQuery() async {
    if (_searchQuery != null && _searchQuery!.length == 4) {
      return await _repository.getPlatesByFourDigit(
        plateFourDigit: _searchQuery!,
        area: currentArea,
      );
    } else {
      // 기본값으로 전체 plates 반환 (필요에 따라 타입 추가 가능)
      return [];
    }
  }

  void setLocationSearchQuery(String query) {
    _locationQuery = query;
    notifyListeners();
  }

  void clearLocationSearchQuery() {
    _locationQuery = null;
    notifyListeners();
  }

  /// 🅿️ 지역 + 주차구역 기준 필터
  List<PlateModel> filterByParkingLocation(PlateType collection, String area, String parkingLocation) {
    debugPrint("🚀 filterByParkingLocation() 호출됨: 지역 = $area, 주차 구역 = $parkingLocation");

    List<PlateModel> plates;

    if (collection == PlateType.departureCompleted) {
      plates = _data[collection]?.where((plate) => plate.area == area && plate.endTime != null).toList() ?? [];
    } else {
      plates = _data[collection]?.where((plate) => plate.area == area).toList() ?? [];
    }

    debugPrint("📌 지역 및 end_time 필터링 후 plate 개수: ${plates.length}");

    plates = plates.where((plate) => plate.location == parkingLocation).toList();

    debugPrint("📌 주차 구역 필터링 후 plate 개수: ${plates.length}");

    return plates;
  }

  /// 🗺️ 선택 가능한 주차 구역
  Future<List<String>> getAvailableLocations(String area) async {
    return await _repository.getAvailableLocations(area);
  }

  /// 🔄 외부 상태 동기화용 호출
  void syncWithAreaState() {
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
