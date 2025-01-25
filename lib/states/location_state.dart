import 'package:flutter/material.dart';
import '../repositories/location_repository.dart';

/// LocationState
/// - Firestore와 동기화하여 주차 구역 데이터를 관리
/// - 선택 상태 및 네비게이션 아이콘 상태를 포함
class LocationState extends ChangeNotifier {
  final LocationRepository _repository;

  LocationState(this._repository) {
    _initializeLocations(); // Firestore 데이터와 동기화
  }

  List<Map<String, String>> _locations = []; // 주차 구역 데이터
  Map<String, bool> _selectedLocations = {}; // 선택된 구역 상태
  bool _isLoading = true; // 로딩 상태
  List<IconData> _navigationIcons = [Icons.add, Icons.circle, Icons.settings]; // 하단 네비게이션 아이콘 상태

  // 주차 구역 데이터 반환
  List<Map<String, String>> get locations => _locations;

  // 선택된 구역 상태 반환
  Map<String, bool> get selectedLocations => _selectedLocations;

  // 로딩 상태 반환
  bool get isLoading => _isLoading;

  // 하단 네비게이션 아이콘 반환
  List<IconData> get navigationIcons => _navigationIcons;

  // 네비게이션 아이콘 상태를 동적으로 정의
  final Map<bool, List<IconData>> _iconStates = {
    true: [Icons.lock, Icons.delete, Icons.edit], // 선택된 상태의 아이콘
    false: [Icons.add, Icons.circle, Icons.settings], // 기본 아이콘
  };

  /// Firestore 데이터 실시간 동기화
  /// - Firestore에서 주차 구역 데이터를 구독하고 상태 업데이트
  void _initializeLocations() {
    _repository.getLocationsStream().listen((data) {
      _updateLocations(data); // 주차 구역 데이터 및 선택 상태 업데이트
      _updateIcons(); // 아이콘 상태 업데이트
      _isLoading = false; // 로딩 완료
      notifyListeners(); // 상태 변경 알림
    }, onError: (error) {
      // Firestore 스트림 에러 처리
      debugPrint('Error syncing locations: $error');
      _isLoading = false;
      notifyListeners();
    });
  }

  /// 주차 구역 데이터 및 선택 상태 업데이트
  void _updateLocations(List<Map<String, dynamic>> data) {
    _locations = data
        .map((location) => {
              'id': location['id'] as String,
              'locationName': location['locationName'] as String,
              'area': location['area'] as String,
            })
        .toList();

    _selectedLocations = {
      for (var location in data) location['id'] as String: location['isSelected'] as bool,
    };
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

  /// 주차 구역 선택 상태 토글
  Future<void> toggleSelection(String id) async {
    final currentState = _selectedLocations[id] ?? false;
    try {
      await _repository.toggleLocationSelection(id, !currentState);
    } catch (e) {
      debugPrint('Error toggling selection: $e');
    }
  }

  /// 네비게이션 아이콘 상태 업데이트
  void _updateIcons() {
    _navigationIcons = _iconStates[_selectedLocations.values.contains(true)]!;
  }
}
