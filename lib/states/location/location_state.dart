import 'package:flutter/material.dart';
import '../../repositories/location/location_repository.dart';
import '../../models/location_model.dart';
import '../area/area_state.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;
  final AreaState _areaState;
  final List<IconData> _navigationIcons = [Icons.add, Icons.delete];

  LocationState(this._repository, this._areaState) {
    syncWithAreaState();
    _areaState.addListener(syncWithAreaState); // 지역 변경 감지
  }

  List<LocationModel> _locations = [];
  Map<String, bool> _selectedLocations = {};
  bool _isLoading = true;

  String _previousArea = '';

  List<LocationModel> get locations => _locations;
  Map<String, bool> get selectedLocations => _selectedLocations;
  bool get isLoading => _isLoading;
  List<IconData> get navigationIcons => _navigationIcons;

  /// ✅ 지역 상태와 동기화 (단발성 조회 기반)
  Future<void> syncWithAreaState() async {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea.isEmpty || _previousArea == currentArea) {
      debugPrint('✅ 위치 재조회 생략: 동일 지역 ($currentArea)');
      return;
    }

    debugPrint('🔥 위치 재조회: $_previousArea → $currentArea');
    _previousArea = currentArea;

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getLocationsOnce(currentArea);
      _locations = data;
      _selectedLocations = {
        for (var loc in data) loc.id: loc.isSelected,
      };
    } catch (e) {
      debugPrint('🔥 위치 동기화 중 오류 발생: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ➕ 단일 주차 구역 추가
  Future<void> addLocation(String locationName, String area, {void Function(String)? onError}) async {
    try {
      await _repository.addLocation(LocationModel(
        id: locationName,
        locationName: locationName,
        area: area,
        parent: area,
        type: 'single',
        isSelected: false,
      ));
      await syncWithAreaState(); // 🔁 추가 후 갱신
    } catch (e) {
      onError?.call('🚨 주차 구역 추가 실패: $e');
    }
  }

  /// ➕ 복합 주차 구역 추가
  Future<void> addCompositeLocation(String parent, List<String> subs, String area,
      {void Function(String)? onError}) async {
    try {
      await _repository.addCompositeLocation(parent, subs, area);
      await syncWithAreaState(); // 🔁 추가 후 갱신
    } catch (e) {
      onError?.call('🚨 복합 주차 구역 추가 실패: $e');
    }
  }

  /// ❌ 주차 구역 삭제
  Future<void> deleteLocations(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteLocations(ids);
      await syncWithAreaState(); // 🔁 삭제 후 갱신
    } catch (e) {
      onError?.call('🚨 주차 구역 삭제 실패: $e');
    }
  }

  /// ✅ 선택 여부 토글
  Future<void> toggleSelection(String id) async {
    final previousState = _selectedLocations[id] ?? false;
    _selectedLocations[id] = !previousState;
    notifyListeners();

    try {
      await _repository.toggleLocationSelection(id, !previousState);
    } catch (e) {
      debugPrint('🔥 선택 상태 전환 오류: $e');
      _selectedLocations[id] = previousState; // 롤백
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _areaState.removeListener(syncWithAreaState);
    super.dispose();
  }
}
