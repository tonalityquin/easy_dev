import 'package:flutter/material.dart';
import '../repositories/location/location_repository.dart';
import '../models/location_model.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;
  LocationState(this._repository) {
    _initializeLocations();
  }

  List<LocationModel> _locations = [];
  Map<String, bool> _selectedLocations = {};
  bool _isLoading = true;
  List<IconData> _navigationIcons = [Icons.add, Icons.delete];

  List<LocationModel> get locations => _locations;
  Map<String, bool> get selectedLocations => _selectedLocations;
  bool get isLoading => _isLoading;
  List<IconData> get navigationIcons => _navigationIcons;

  void _initializeLocations() {
    _repository.getLocationsStream().listen(
          (data) {
        _locations = data;
        _selectedLocations = { for (var loc in data) loc.id: loc.isSelected };
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Error syncing locations: $error');
      },
    );
  }

  Future<void> addLocation(String locationName, String area, {void Function(String)? onError}) async {
    try {
      await _repository.addLocation(LocationModel(id: locationName, locationName: locationName, area: area, isSelected: false));
    } catch (e) {
      onError?.call('🚨 주차 구역 추가 실패: $e');
    }
  }

  Future<void> deleteLocations(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteLocations(ids);
    } catch (e) {
      onError?.call('🚨 주차 구역 삭제 실패: $e');
    }
  }

  Future<void> toggleSelection(String id) async {
    final previousState = _selectedLocations[id] ?? false;
    _selectedLocations[id] = !previousState;
    notifyListeners();
    try {
      await _repository.toggleLocationSelection(id, !previousState);
    } catch (e) {
      debugPrint('Error toggling selection: $e');
      _selectedLocations[id] = previousState;
      notifyListeners();
    }
  }
}
