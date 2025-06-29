import 'dart:async';
import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';

class FilterPlate extends ChangeNotifier {
  // 🔹 1. 필드
  final PlateRepository _repository;
  final String currentArea;

  final Map<PlateType, List<PlateModel>> _data = {
    for (var type in PlateType.values) type: [],
  };

  final Map<PlateType, StreamSubscription<List<PlateModel>>> _subscriptions = {};

  String? _searchQuery;
  String? _locationQuery;

  /// 🕰 캐싱을 위한 필드
  final Map<String, List<PlateModel>> _plateCache = {};

  // 🔹 2. 생성자
  FilterPlate(this._repository, this.currentArea) {
    debugPrint("✅ FilterPlate created with area: $currentArea");
    _initializeFilterData();
  }

  // 🔹 3. 게터
  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  // 🔹 4. Public 메서드

  /// 🔁 지역 기반으로 PlateType별 스트림 구독 초기화
  void _initializeFilterData() {
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

  void clearLocationSearchQuery() {
    _locationQuery = null;
    notifyListeners();
  }

  List<PlateModel> filterPlateCountByQuery(List<PlateModel> plates) {
    if (_searchQuery != null && _searchQuery!.length == 4) {
      return plates.where((plate) => plate.plateFourDigit == _searchQuery).toList();
    }
    return plates;
  }

  Future<List<PlateModel>> fetchPlatesCountsBySearchQuery() async {
    if (_searchQuery != null && _searchQuery!.length == 4) {
      return await _repository.getPlatesByFourDigit(
        plateFourDigit: _searchQuery!,
        area: currentArea,
      );
    } else {
      return [];
    }
  }

  Future<List<PlateModel>> fetchPlatesByParkingLocationWithCache({
    required PlateType type,
    required String location,
  }) async {
    final cacheKey = '${currentArea}_${location}_${type.firestoreValue}';
    final cached = _getCached(cacheKey);

    if (cached != null) {
      debugPrint('✅ 캐시 반환: $cacheKey (${cached.length}건)');
      return cached;
    }

    debugPrint('🔥 Firestore 호출: $cacheKey');
    final plates = await _repository.getPlatesByLocation(
      type: type,
      area: currentArea,
      location: location,
    );

    _setCache(cacheKey, plates);
    return plates;
  }

  List<PlateModel> filterByParkingLocation(
      PlateType collection, String area, String parkingLocation) {
    debugPrint("🚀 filterByParkingLocation() 호출됨: 지역 = $area, 주차 구역 = $parkingLocation");

    List<PlateModel> plates;

    if (collection == PlateType.departureCompleted) {
      plates = _data[collection]
          ?.where((plate) => plate.area == area && plate.endTime != null)
          .toList() ??
          [];
    } else {
      plates = _data[collection]?.where((plate) => plate.area == area).toList() ?? [];
    }

    debugPrint("📌 지역 및 end_time 필터링 후 plate 개수: ${plates.length}");

    plates = plates.where((plate) => plate.location == parkingLocation).toList();

    debugPrint("📌 주차 구역 필터링 후 plate 개수: ${plates.length}");

    return plates;
  }

  // 🔹 5. Private 메서드
  List<PlateModel>? _getCached(String key) {
    return _plateCache[key]; // 유효 기간 검사 없이 캐시에 있으면 반환
  }

  void _setCache(String key, List<PlateModel> plates) {
    _plateCache[key] = plates;
  }

  // 🔹 6. Override
  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
