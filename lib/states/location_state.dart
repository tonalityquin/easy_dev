import 'package:flutter/material.dart';
import '../repositories/location_repository.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;

  LocationState(this._repository) {
    _initializeLocations();
  }

  List<Map<String, String>> _locations = [];
  Map<String, bool> _selectedLocations = {};
  bool _isLoading = true;
  List<IconData> _navigationIcons = [Icons.add, Icons.circle, Icons.settings];

  List<Map<String, String>> get locations => _locations;

  Map<String, bool> get selectedLocations => _selectedLocations;

  bool get isLoading => _isLoading;

  List<IconData> get navigationIcons => _navigationIcons;
  final Map<bool, List<IconData>> _iconStates = {
    true: [Icons.lock, Icons.delete, Icons.edit],
    false: [Icons.add, Icons.circle, Icons.settings],
  };

  void _initializeLocations() {
    _repository.getLocationsStream().listen(
      (data) {
        _updateLocations(data);
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) => _handleFirestoreError('Error syncing locations', error),
    );
  }

  void _updateLocations(List<Map<String, dynamic>> data) {
    _locations = data.map((location) {
      String id = location['id'] as String;
      return {
        'id': id,
        'locationName': location['locationName'] as String,
        'area': location['area'] as String,
      };
    }).toList();
    _selectedLocations = {
      for (var location in data) location['id'] as String: location['isSelected'] as bool,
    };
    _updateIcons();
  }

  void _updateIcons() {
    _navigationIcons = _iconStates[_selectedLocations.values.contains(true)]!;
  }

  Future<void> addLocation(String locationName, String area, {void Function(String)? onError}) async {
    try {
      await _repository.addLocation(locationName, area);
    } catch (e) {
      _handleFirestoreError('Error adding location', e, onError); // 🔥 안전한 전달
    }
  }

  Future<void> deleteLocations(List<String> ids, {required void Function(String) onError}) async {
    try {
      await _repository.deleteLocations(ids);
    } catch (e) {
      _handleFirestoreError('Error deleting location', e, onError);
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

  void _handleFirestoreError(String message, dynamic error, [void Function(String)? onError]) {
    debugPrint('$message: $error');
    onError?.call('🚨 $message: $error');
  }
}
