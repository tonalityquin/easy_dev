import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../area/area_state.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;

  PlateState(this._repository, this._areaState) {
    _initializeSubscriptions();
    _areaState.addListener(_onAreaChanged);
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

  void _initializeSubscriptions() {
    _cancelAllSubscriptions();

    _isLoading = true;
    PlateCounts();

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
          PlateCounts();
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
    _initializeSubscriptions();
  }

  void syncWithAreaState() {
    print("🔄 지역 동기화 수동 호출됨(: $currentArea");
    PlateCounts();
  }

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

      if (plate.isSelected && plate.selectedBy != userName) {
        throw Exception('⚠️ 이미 다른 사용자가 선택한 번호판입니다.');
      }

      final alreadySelected = _data.entries.expand((entry) => entry.value).firstWhere(
            (p) => p.isSelected && p.selectedBy == userName && p.id != plateId,
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

      if (alreadySelected.id.isNotEmpty && !plate.isSelected) {
        final collectionLabel = _getCollectionLabelForType(alreadySelected.type);
        throw Exception('⚠️ 이미 다른 번호판을 선택한 상태입니다.\n'
            '• 선택된 번호판: ${alreadySelected.plateNumber}\n'
            '• 위치: $collectionLabel\n'
            '선택을 해제한 후 다시 시도해주세요.');
      }

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
      onError('🚨 번호판 선택 상태 변경 실패:\n$e');
    }
  }

  String _getCollectionLabelForType(String type) {
    switch (type) {
      case '입차 요청':
      case '입차 중':
        return '입차 요청';
      case '입차 완료':
        return '입차 완료';
      case '출차 요청':
        return '출차 요청';
      case '출차 완료':
        return '출차 완료';
      default:
        return '알 수 없음';
    }
  }

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
    _initializeSubscriptions();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
