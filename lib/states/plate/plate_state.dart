import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../area/area_state.dart';
import '../../enums/plate_collection.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;

  PlateState(this._repository, this._areaState) {
    _initializeSubscriptions();
    _areaState.addListener(_onAreaChanged);
  }

  final Map<PlateCollection, List<PlateModel>> _data = {
    for (var c in PlateCollection.values) c: [],
  };

  final Map<PlateCollection, Stream<List<PlateModel>>> _activeStreams = {};
  final Map<PlateCollection, StreamSubscription<List<PlateModel>>> _subscriptions = {};

  String? _searchQuery;

  String get searchQuery => _searchQuery ?? "";

  String get currentArea => _areaState.currentArea;

  bool _isLoading = true;

  bool get isLoading => _isLoading;

  void plateCounts() {
    if (_isLoading) {
      debugPrint('🕐 지역 Plate 상태 수신 대기 중...');
    } else {
      debugPrint('✅ 지역 Plate 상태 수신 완료');
      debugPrint('📌 Selected Area: $currentArea');
      debugPrint('🅿️ Parking Requests: ${_data[PlateCollection.parkingRequests]?.length ?? 0}');
      debugPrint('✅ Parking Completed: ${_data[PlateCollection.parkingCompleted]?.length ?? 0}');
      debugPrint('🚗 Departure Requests: ${_data[PlateCollection.departureRequests]?.length ?? 0}');
      debugPrint('🏁 Departure Completed: ${_data[PlateCollection.departureCompleted]?.length ?? 0}');
    }
  }

  int getDepartureCompletedCountByDate(DateTime selectedDate) {
    return _data[PlateCollection.departureCompleted]
        ?.where((p) =>
    p.endTime != null &&
        p.endTime!.year == selectedDate.year &&
        p.endTime!.month == selectedDate.month &&
        p.endTime!.day == selectedDate.day)
        .length ??
        0;
  }

  void _initializeSubscriptions() {
    _cancelAllSubscriptions();

    _isLoading = true;
    plateCounts();

    int receivedCount = 0;
    final totalCollections = PlateCollection.values.length;

    for (final collection in PlateCollection.values) {
      final stream = _repository
          .getCollectionStream(collection.name)
          .map((list) => list.where((plate) => plate.area == currentArea).toList());

      _activeStreams[collection] = stream;

      bool firstDataReceived = false;

      final subscription = stream.listen((filteredData) {
        if (!listEquals(_data[collection], filteredData)) {
          _data[collection] = filteredData;
          notifyListeners();
        }

        if (!firstDataReceived) {
          firstDataReceived = true;
          receivedCount++;
        }

        if (receivedCount == totalCollections) {
          _isLoading = false;
          plateCounts();
        }
      });

      _subscriptions[collection] = subscription;
    }
  }

  void _cancelAllSubscriptions() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _onAreaChanged() {
    debugPrint("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _initializeSubscriptions();
  }

  void syncWithAreaState() {
    debugPrint("🔄 지역 동기화 수동 호출됨(: $currentArea");
    plateCounts();
  }

  List<PlateModel> getPlatesByCollection(PlateCollection collection, {DateTime? selectedDate}) {
    List<PlateModel> plates = _data[collection] ?? [];

    if (collection == PlateCollection.departureCompleted) {
      plates = plates.where((plate) {
        if (plate.endTime == null) return false;
        if (selectedDate == null) return true;

        return plate.endTime!.year == selectedDate.year &&
            plate.endTime!.month == selectedDate.month &&
            plate.endTime!.day == selectedDate.day;
      }).toList();
    }

    if (_searchQuery != null && _searchQuery!.length == 4) {
      plates = plates.where((plate) {
        final last4Digits = plate.plateNumber.length >= 4
            ? plate.plateNumber.substring(plate.plateNumber.length - 4)
            : plate.plateNumber;
        return last4Digits == _searchQuery;
      }).toList();
    }

    return plates;
  }

  Future<void> toggleIsSelected({
    required PlateCollection collection,
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
        collection.name,
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

  PlateModel? getSelectedPlate(PlateCollection collection, String userName) {
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

  Future<void> updatePlateLocally(PlateCollection collection, PlateModel updatedPlate) async {
    final list = _data[collection];
    if (list == null) return;

    final index = list.indexWhere((p) => p.id == updatedPlate.id);
    if (index != -1) {
      _data[collection]![index] = updatedPlate;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
