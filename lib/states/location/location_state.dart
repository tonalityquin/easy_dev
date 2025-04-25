import 'package:flutter/material.dart';
import '../../repositories/location/location_repository.dart';
import '../../models/location_model.dart';
import '../area/area_state.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;
  final List<IconData> _navigationIcons = [Icons.add, Icons.delete];
  final AreaState _areaState;

  LocationState(this._repository, this._areaState) {
    _initializeLocations();
  }

  List<LocationModel> _locations = [];
  Map<String, bool> _selectedLocations = {};
  bool _isLoading = true;

  List<LocationModel> get locations => _locations;

  Map<String, bool> get selectedLocations => _selectedLocations;

  bool get isLoading => _isLoading;

  List<IconData> get navigationIcons => _navigationIcons;

  // 🔄 지역 기반 Location 스트림 초기화
  void _initializeLocations() {
    final currentArea = _areaState.currentArea.trim();

    _repository.getLocationsStream(currentArea).listen(
          (data) {
        _locations = data;
        _selectedLocations = {
          for (var loc in data) loc.id: loc.isSelected,
        };
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('🔥 위치 동기화 중 오류 발생: $error');
      },
    );
  }

  // ➕ 주차 구역 추가
  Future<void> addLocation(String locationName, String area, {void Function(String)? onError}) async {
    try {
      await _repository.addLocation(LocationModel(
        id: locationName,
        locationName: locationName,
        area: area,
        isSelected: false,
      ));
    } catch (e) {
      onError?.call('🚨 주차 구역 추가 실패: $e');
    }
  }

  // ❌ 주차 구역 삭제
  Future<void> deleteLocations(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteLocations(ids);
    } catch (e) {
      onError?.call('🚨 주차 구역 삭제 실패: $e');
    }
  }

  // ✅ 주차 구역 선택 토글
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
}
