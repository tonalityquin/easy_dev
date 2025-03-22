import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../area/area_state.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;

  PlateState(this._repository, this._areaState) {
    _initializeSubscriptions();
    _areaState.addListener(_onAreaChanged); // ✅ 지역 변경 감지 리스너
  }

  final Map<String, List<PlateModel>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  final Map<String, Stream<List<PlateModel>>> _activeStreams = {};
  final Map<String, StreamSubscription<List<PlateModel>>> _subscriptions = {};

  String? _searchQuery;

  String get searchQuery => _searchQuery ?? "";

  String get currentArea => _areaState.currentArea;

  bool _isLoading = true;

  bool get isLoading => _isLoading;

  /// 🔹 개수 출력 (로딩 상태 반영)
  void PlateCounts() {
    if (_isLoading) {
      print('🕐 지역 Plate 상태 수신 대기 중...');
    } else {
      print('✅ 지역 Plate 상태 수신 완료');
      print('📌 Selected Area: $currentArea');
      print('🅿️ Parking Requests: ${_data['parking_requests']?.length ?? 0}');
      print('✅ Parking Completed: ${_data['parking_completed']?.length ?? 0}');
      print('🚗 Departure Requests: ${_data['departure_requests']?.length ?? 0}');
      print('🏁 Departure Completed: ${_data['departure_completed']?.length ?? 0}');
    }
  }

  /// 🔄 모든 컬렉션 스트림 재구독 + 로딩 상태 처리
  void _initializeSubscriptions() {
    _cancelAllSubscriptions();

    _isLoading = true;
    PlateCounts(); // 🕐 출력

    int receivedCount = 0;
    final totalCollections = _data.keys.length;

    for (final collectionName in _data.keys) {
      final stream = _repository
          .getCollectionStream(collectionName)
          .map((list) => list.where((plate) => plate.area == currentArea).toList());

      _activeStreams[collectionName] = stream;

      bool firstDataReceived = false;

      final subscription = stream.listen((filteredData) {
        if (!listEquals(_data[collectionName], filteredData)) {
          _data[collectionName] = filteredData;
          notifyListeners();
        }

        if (!firstDataReceived) {
          firstDataReceived = true;
          receivedCount++;
        }

        if (receivedCount == totalCollections) {
          _isLoading = false;
          PlateCounts(); // ✅ 모든 스트림 완료 시점에 한 번만 출력
        }
      });

      _subscriptions[collectionName] = subscription;
    }
  }

  void _cancelAllSubscriptions() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _onAreaChanged() {
    print("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _initializeSubscriptions(); // ✅ 지역 변경 → 스트림 재설정
  }

  void syncWithAreaState() {
    print("🔄 지역 동기화 수동 호출됨(: $currentArea");
    PlateCounts();
  }

  /// 🔍 현재 지역에 해당하는 plate 데이터를 가져오는 함수
  List<PlateModel> getPlatesByCollection(String collection) {
    final plates = _data[collection] ?? [];

    if (_searchQuery != null && _searchQuery!.length == 4) {
      return plates.where((plate) {
        final last4Digits = plate.plateNumber.length >= 4
            ? plate.plateNumber.substring(plate.plateNumber.length - 4)
            : plate.plateNumber;
        return last4Digits == _searchQuery;
      }).toList();
    }
    return plates;
  }

  /// ✅ 특정 plate 선택 상태를 토글
  Future<void> toggleIsSelected({
    required String collection,
    required String plateNumber,
    required String userName,
    required void Function(String) onError,
  }) async {
    final plateId = '${plateNumber}_$currentArea';
    try {
      final plateList = _data[collection];
      if (plateList == null) throw Exception('🚨 Collection not found');
      final index = plateList.indexWhere((p) => p.id == plateId);
      if (index == -1) throw Exception('🚨 Plate not found');

      final plate = plateList[index];
      final newIsSelected = !plate.isSelected;
      final newSelectedBy = newIsSelected ? userName : null;

      await _repository.updatePlateSelection(
        collection,
        plateId,
        newIsSelected,
        selectedBy: newSelectedBy,
      );

      _data[collection]![index] = plate.copyWith(
        isSelected: newIsSelected,
        selectedBy: newSelectedBy,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error toggling isSelected: $e');
      onError('🚨 번호판 선택 상태 변경 실패: $e');
    }
  }

  /// 🔍 현재 유저가 선택한 plate 조회
  PlateModel? getSelectedPlate(String collection, String userName) {
    final plates = _data[collection];
    if (plates == null || plates.isEmpty) return null;

    return plates.firstWhere(
      (plate) => plate.isSelected && plate.selectedBy == userName,
      orElse: () => PlateModel(
        id: '',
        plateNumber: '',
        type: '',
        requestTime: DateTime.now(),
        location: '',
        area: '',
        userName: '',
        isSelected: false,
        statusList: [],
      ),
    );
  }

  Future<void> fetchPlateData() async {
    _initializeSubscriptions(); // 🔁 기존 스트림 초기화 및 재구독
  }

  /// 🔁 외부에서 수동으로 재동기화할 경우 호출
  @override
  void dispose() {
    _cancelAllSubscriptions();
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
