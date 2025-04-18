import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';

class FilterPlate extends ChangeNotifier {
  final PlateRepository _repository;

  FilterPlate(this._repository) {
    _initializeData();
  }

  final Map<PlateType, List<PlateModel>> _data = {
    for (var type in PlateType.values) type: [],
  };

  String? _searchQuery;
  String? _locationQuery;

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  void _initializeData() {
    for (final plateType in PlateType.values) {
      _repository.getPlatesByType(plateType).listen((data) {
        _data[plateType] = data;
        notifyListeners();
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

  void setLocationSearchQuery(String query) {
    _locationQuery = query;
    notifyListeners();
  }

  void clearLocationSearchQuery() {
    _locationQuery = null;
    notifyListeners();
  }

  List<PlateModel> filterPlatesByQuery(List<PlateModel> plates) {
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

  List<PlateModel> filterByParkingLocation(PlateType collection, String area, String parkingLocation) {
    debugPrint("🚀 filterByParkingLocation() 호출됨: 지역 = $area, 주차 구역 = $parkingLocation");

    List<PlateModel> plates;

    if (collection == PlateType.departureCompleted) {
      // ✅ 출차 완료만: area + end_time 필터
      plates = _data[collection]?.where((plate) => plate.area == area && plate.endTime != null).toList() ?? [];
    } else {
      plates = _data[collection]?.where((plate) => plate.area == area).toList() ?? [];
    }

    debugPrint("📌 지역 및 end_time 필터링 후 plate 개수: ${plates.length}");

    plates = plates.where((plate) => plate.location == parkingLocation).toList();

    debugPrint("📌 주차 구역 필터링 후 plate 개수: ${plates.length}");

    return plates;
  }

  List<PlateModel> filterDepartureCompletedByDate({
    required String area,
    required DateTime selectedDate,
  }) {
    return _data[PlateType.departureCompleted]
            ?.where((plate) =>
                plate.area == area &&
                plate.endTime != null &&
                plate.endTime!.year == selectedDate.year &&
                plate.endTime!.month == selectedDate.month &&
                plate.endTime!.day == selectedDate.day)
            .toList() ??
        [];
  }

  Future<List<String>> getAvailableLocations(String area) async {
    return await _repository.getAvailableLocations(area);
  }

  void syncWithAreaState() {
    notifyListeners();
  }
}
