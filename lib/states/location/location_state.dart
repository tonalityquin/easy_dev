import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../repositories/location/location_repository.dart';
import '../../models/location_model.dart';
import '../area/area_state.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;
  final AreaState _areaState;
  final List<IconData> _navigationIcons = [Icons.add, Icons.delete];

  List<LocationModel> _locations = [];
  String? _selectedLocationId;
  String _previousArea = '';
  bool _isLoading = true;

  List<LocationModel> get locations => _locations;

  List<IconData> get navigationIcons => _navigationIcons;

  String? get selectedLocationId => _selectedLocationId;

  bool get isLoading => _isLoading;

  LocationState(this._repository, this._areaState) {
    loadFromLocationCache();

    _areaState.addListener(() async {
      final currentArea = _areaState.currentArea.trim();
      if (currentArea != _previousArea) {
        _previousArea = currentArea;
        await loadFromLocationCache();
      }
    });
  }

  Future<void> loadFromLocationCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();
    final cachedJson = prefs.getString('cached_locations_$currentArea');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _locations = decoded.map((e) => LocationModel.fromCacheMap(Map<String, dynamic>.from(e))).toList();
        _selectedLocationId = null;
        _previousArea = currentArea;
        _isLoading = false;
        notifyListeners();
        debugPrint('✅ 캐시에서 주차 구역 ${_locations.length}건 로드 (area: $currentArea)');

        final totalCapacity = prefs.getInt('total_capacity_$currentArea') ?? 0;
        debugPrint('📦 총 capacity 캐시값: $totalCapacity');
      } catch (e) {
        debugPrint('⚠️ 주차 구역 캐시 디코딩 실패: $e');
      }
    } else {
      debugPrint('⚠️ 캐시에 없음 → Firestore 호출 없음 (수동 새로고침에서만 호출)');
      _locations = [];
      _selectedLocationId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> manualLocationRefresh() async {
    final currentArea = _areaState.currentArea.trim();
    debugPrint('🔥 수동 새로고침 Firestore 호출 → $currentArea');

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getLocationsOnce(currentArea);

      final currentIds = _locations.map((e) => e.id).toSet();
      final newIds = data.map((e) => e.id).toSet();
      final isIdentical = currentIds.length == newIds.length && currentIds.containsAll(newIds);

      if (isIdentical) {
        debugPrint('✅ Firestore 데이터가 캐시와 동일 → 갱신 없음');
      } else {
        _locations = data;
        _selectedLocationId = null;

        final prefs = await SharedPreferences.getInstance();

        final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
        await prefs.setString('cached_locations_$currentArea', jsonData);

        final totalCapacity = data.fold<int>(0, (sum, loc) => sum + loc.capacity);
        await prefs.setInt('total_capacity_$currentArea', totalCapacity);

        debugPrint('✅ Firestore 데이터 캐시에 갱신됨 (area: $currentArea)');
        debugPrint('📦 총 capacity 저장됨: $totalCapacity');
      }
    } catch (e) {
      debugPrint('🔥 Firestore 주차 구역 조회 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updatePlateCounts(Map<String, int> counts) {
    _locations = _locations.map((loc) {
      final fullName = loc.type == 'composite' ? '${loc.parent} - ${loc.locationName}' : loc.locationName;

      final count = counts[fullName] ?? 0;
      return loc.copyWith(plateCount: count);
    }).toList();

    notifyListeners();
    debugPrint('📊 plateCount 업데이트 완료 (${counts.length}건)');
  }

  Future<void> updatePlateCountsFromRepository(LocationRepository repo) async {
    final names = _locations.map((loc) {
      return loc.type == 'composite' ? '${loc.parent} - ${loc.locationName}' : loc.locationName;
    }).toList();

    final counts = await repo.getPlateCountsForLocations(
      locationNames: names,
      area: _areaState.currentArea,
    );

    updatePlateCounts(counts);
  }

  Future<void> addSingleLocation(
    String locationName,
    String area, {
    int capacity = 0,
    void Function(String)? onError,
  }) async {
    try {
      final location = LocationModel(
        id: '${locationName}_$area',
        locationName: locationName,
        area: area,
        parent: area,
        type: 'single',
        capacity: capacity,
        isSelected: false,
      );

      await _repository.addSingleLocation(location);
      await loadFromLocationCache();
    } catch (e) {
      onError?.call('🚨 주차 구역 추가 실패: $e');
    }
  }

  Future<void> addCompositeLocation(
    String parent,
    List<Map<String, dynamic>> subs,
    String area, {
    void Function(String)? onError,
  }) async {
    try {
      final safeParent = '${parent}_$area';
      final safeSubs = subs.map((sub) {
        final subName = sub['name'];
        return {'name': '${subName}_$area', 'capacity': sub['capacity'] ?? 0};
      }).toList();

      await _repository.addCompositeLocation(safeParent, safeSubs, area);
      await loadFromLocationCache();
    } catch (e) {
      onError?.call('🚨 복합 주차 구역 추가 실패: $e');
    }
  }

  Future<void> deleteLocations(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.deleteLocations(ids);
      await loadFromLocationCache();
    } catch (e) {
      onError?.call('🚨 주차 구역 삭제 실패: $e');
    }
  }

  Future<void> toggleLocationSelection(String id) async {
    if (_selectedLocationId == id) {
      _selectedLocationId = null;
    } else {
      _selectedLocationId = id;
    }
    notifyListeners();
  }
}
