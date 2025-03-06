import 'package:flutter/material.dart';
import '../repositories/location_repository.dart';

/// **LocationState 클래스**
/// - Firestore와 동기화하여 주차 구역 데이터를 관리
/// - 선택 상태 및 네비게이션 아이콘 상태 포함
class LocationState extends ChangeNotifier {
  final LocationRepository _repository;

  LocationState(this._repository) {
    _initializeLocations(); // Firestore 데이터와 동기화
  }

  List<Map<String, String>> _locations = []; // 주차 구역 데이터
  Map<String, bool> _selectedLocations = {}; // 선택된 구역 상태
  bool _isLoading = true; // 로딩 상태
  List<IconData> _navigationIcons = [Icons.add, Icons.circle, Icons.settings]; // 네비게이션 아이콘 상태

  // **Getter**
  List<Map<String, String>> get locations => _locations;

  Map<String, bool> get selectedLocations => _selectedLocations;

  bool get isLoading => _isLoading;

  List<IconData> get navigationIcons => _navigationIcons;

  // **네비게이션 아이콘 상태 정의**
  final Map<bool, List<IconData>> _iconStates = {
    true: [Icons.lock, Icons.delete, Icons.edit], // 선택된 상태의 아이콘
    false: [Icons.add, Icons.circle, Icons.settings], // 기본 아이콘
  };

  /// **Firestore 데이터 실시간 동기화**
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

  /// **주차 구역 데이터 및 선택 상태 업데이트**
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

    _updateIcons(); // 🔹 선택 상태 변경 시 네비게이션 아이콘 자동 변경
  }

  /// **네비게이션 아이콘 상태 업데이트**
  void _updateIcons() {
    _navigationIcons = _iconStates[_selectedLocations.values.contains(true)]!;
  }

  /// **Firestore에 주차 구역 추가**
  Future<void> addLocation(String locationName, String area, {void Function(String)? onError}) async {
    try {
      await _repository.addLocation(locationName, area);
    } catch (e) {
      _handleFirestoreError('Error adding location', e, onError); // 🔥 안전한 전달
    }
  }


  /// **Firestore에서 주차 구역 삭제**
  Future<void> deleteLocations(List<String> ids, {required void Function(String) onError}) async {
    try {
      await _repository.deleteLocations(ids);
    } catch (e) {
      _handleFirestoreError('Error deleting location', e, onError);
    }
  }

  /// **주차 구역 선택 상태 토글**
  Future<void> toggleSelection(String id) async {
    final previousState = _selectedLocations[id] ?? false;
    _selectedLocations[id] = !previousState;
    notifyListeners(); // UI 즉시 업데이트

    try {
      await _repository.toggleLocationSelection(id, !previousState);
    } catch (e) {
      debugPrint('Error toggling selection: $e');
      _selectedLocations[id] = previousState; // 🔹 Firestore 실패 시 기존 상태 복구
      notifyListeners();
    }
  }

  /// **Firestore 오류 처리 함수**
  void _handleFirestoreError(String message, dynamic error, [void Function(String)? onError]) {
    debugPrint('$message: $error');
    onError?.call('🚨 $message: $error'); // 🔥 안전한 호출
  }
}
