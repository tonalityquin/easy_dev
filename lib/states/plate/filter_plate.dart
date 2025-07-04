import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'plate_state.dart';

class FilterPlate extends ChangeNotifier {
  // 🔹 1. 필드
  final PlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

  // 🔹 2. 생성자
  FilterPlate(this._plateState);

  // 🔹 3. 게터
  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  // 🔹 4. Public 메서드

  /// ✅ 검색어 설정
  void setPlateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearPlateSearchQuery() {
    _searchQuery = null;
    notifyListeners();
  }

  void clearLocationSearchQuery() {
    _locationQuery = null;
    notifyListeners();
  }

  List<PlateModel> filterPlatesByFourDigit(String fourDigit) {
    final all = _plateState.dataOfType(PlateType.parkingRequests);
    return all.where((p) => p.plateFourDigit == fourDigit).toList();
  }

  /// ✅ 현재 PlateState 데이터에서 필터링
  List<PlateModel> filterByParkingLocation(
      PlateType collection,
      String parkingLocation,
      ) {
    final all = _plateState.dataOfType(collection);

    var plates = all;

    if (collection == PlateType.departureCompleted) {
      plates = plates.where((plate) => plate.endTime != null).toList();
    }

    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      plates = plates.where((plate) => plate.plateNumber.contains(_searchQuery!)).toList();
    }

    if (parkingLocation.isNotEmpty) {
      plates = plates.where((plate) => plate.location == parkingLocation).toList();
    }

    return plates;
  }

  /// ✅ PlateState에서 특정 PlateType 데이터 가져오기
  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
