import 'package:flutter/material.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';

class FilterPlate extends ChangeNotifier {
  final PlateRepository _repository;

  FilterPlate(this._repository) {
    _initializeData();
  }

  final Map<String, List<PlateModel>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  String? _searchQuery;
  String? _locationQuery;

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  void _initializeData() {
    for (final collection in _data.keys) {
      _repository.getCollectionStream(collection).listen((data) {
        _data[collection] = data;
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

  List<PlateModel> filterByParkingLocation(String collection, String area, String parkingLocation) {
    debugPrint("🚀 filterByParkingLocation() 호출됨: 지역 = $area, 주차 구역 = $parkingLocation");

    List<PlateModel> plates = _data[collection]?.where((plate) => plate.area == area).toList() ?? [];
    debugPrint("📌 지역 필터링 후 plate 개수: ${plates.length}");

    plates = plates.where((plate) => plate.location == parkingLocation).toList();
    debugPrint("📌 주차 구역 필터링 후 plate 개수: ${plates.length}");

    return plates;
  }

  Future<List<String>> getAvailableLocations(String area) async {
    return await _repository.getAvailableLocations(area);
  }

  void syncWithAreaState() {
    notifyListeners();
  }
}
