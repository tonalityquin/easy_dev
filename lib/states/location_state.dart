import 'package:flutter/material.dart';
import '../repositories/location_repository.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;

  LocationState(this._repository) {
    _initializeLocations(); // Firestore 데이터 동기화
  }

  List<Map<String, String>> _locations = [];
  Map<String, bool> _selectedLocations = {};
  bool _isLoading = true;

  List<IconData> _navigationIcons = [
    Icons.add,
    Icons.circle,
    Icons.settings,
  ];

  List<Map<String, String>> get locations => _locations;

  Map<String, bool> get selectedLocations => _selectedLocations;

  bool get isLoading => _isLoading;

  List<IconData> get navigationIcons => _navigationIcons;

  /// Firestore 데이터 실시간 동기화
  void _initializeLocations() {
    _repository.getLocationsStream().listen((data) {
      _locations = data
          .map((location) => {
        'id': location['id'] as String,
        'locationName': location['locationName'] as String,
        'area': location['area'] as String,
      })
          .toList();

      _selectedLocations = {
        for (var location in data)
          location['id'] as String: location['isSelected'] as bool,
      };

      _updateIcons();
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Firestore에 주차 구역 추가
  Future<void> addLocation(String locationName, String area) async {
    try {
      await _repository.addLocation(locationName, area);
    } catch (e) {
      debugPrint('Error adding location: $e');
    }
  }

  /// Firestore에서 주차 구역 삭제
  Future<void> deleteLocations(List<String> ids) async {
    try {
      await _repository.deleteLocations(ids);
    } catch (e) {
      debugPrint('Error deleting location: $e');
    }
  }

  /// 선택 상태 토글
  Future<void> toggleSelection(String id) async {
    final currentState = _selectedLocations[id] ?? false;
    try {
      await _repository.toggleLocationSelection(id, !currentState);
    } catch (e) {
      debugPrint('Error toggling selection: $e');
    }
  }

  /// 아이콘 상태 업데이트
  void _updateIcons() {
    if (_selectedLocations.values.contains(true)) {
      _navigationIcons = [Icons.lock, Icons.delete, Icons.edit];
    } else {
      _navigationIcons = [Icons.add, Icons.circle, Icons.settings];
    }
  }
}
