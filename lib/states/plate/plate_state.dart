import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../repositories/plate/plate_repository.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../area/area_state.dart';

import '../../utils/gcs_uploader.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;

  PlateState(this._repository, this._areaState) {
    _initializeSubscriptions();
    _areaState.addListener(_onAreaChanged);
  }

  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: [],
  };

  final Map<PlateType, StreamSubscription<List<PlateModel>>> _subscriptions = {};
  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  String? _searchQuery;
  String _previousArea = '';
  bool _isLoading = true;

  bool get isLoading => _isLoading;

  String get searchQuery => _searchQuery ?? "";

  String get currentArea => _areaState.currentArea;

  final Map<String, bool> previousIsLockedFee = {};

  void _initializeSubscriptions() async {
    final area = _areaState.currentArea;
    if (area.isEmpty || _previousArea == area) return;

    _previousArea = area;
    _cancelAllSubscriptions();

    _isLoading = true;
    plateCounts();

    int receivedCount = 0;
    final totalCollections = PlateType.values.length;

    for (final collection in PlateType.values) {
      final descending = _isSortedMap[collection] ?? true;

      final stream = _repository.getPlatesByTypeAndArea(
        collection,
        currentArea,
        descending: descending,
      );

      bool firstDataReceived = false;

      final subscription = stream.listen((filteredData) async {
        if (collection == PlateType.departureCompleted) {
          for (final plate in filteredData) {
            final previous = previousIsLockedFee[plate.id];
            if (previous == false && plate.isLockedFee == true) {
              final uploader = GCSUploader();
              await uploader.mergeAndSummarizeLogs(
                plate.plateNumber,
                _areaState.currentDivision,
                plate.area,
              );
            }
            previousIsLockedFee[plate.id] = plate.isLockedFee;
          }
        }

        _data[collection] = filteredData;
        notifyListeners();

        if (!firstDataReceived) {
          firstDataReceived = true;
          receivedCount++;
        }

        if (receivedCount == totalCollections) {
          _isLoading = false;
          plateCounts();
        }
      }, onError: (error) {
        debugPrint('🔥 Plate stream error: $error');
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

  void plateCounts() {
    if (_isLoading) {
      debugPrint('🕐 지역 Plate 상태 수신 대기 중...');
    } else {
      debugPrint('✅ 지역 Plate 상태 수신 완료');
      debugPrint('📌 Selected Area: $currentArea');
      debugPrint('🅿️ Parking Requests: ${_data[PlateType.parkingRequests]?.length ?? 0}');
      debugPrint('✅ Parking Completed: ${_data[PlateType.parkingCompleted]?.length ?? 0}');
      debugPrint('🚗 Departure Requests: ${_data[PlateType.departureRequests]?.length ?? 0}');
      debugPrint('🏁 Departure Completed: ${_data[PlateType.departureCompleted]?.length ?? 0}');
    }
  }

  List<PlateModel> getPlatesByCollection(PlateType collection, {DateTime? selectedDate}) {
    List<PlateModel> plates = _data[collection] ?? [];

    if (collection == PlateType.departureCompleted && selectedDate != null) {
      final selectedDateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      plates = plates.where((plate) {
        final end = plate.endTime;
        if (end == null) return false;
        final endDate = DateTime(end.year, end.month, end.day);
        return endDate == selectedDateOnly;
      }).toList();
    }

    if (_searchQuery != null && _searchQuery!.length == 4) {
      plates = plates.where((plate) => plate.plateFourDigit == _searchQuery).toList();
    }

    return plates;
  }

  void updateSortOrder(PlateType type, bool descending) {
    _isSortedMap[type] = descending;
    _resubscribeForType(type);
  }

  void _resubscribeForType(PlateType type) async {
    final area = _areaState.currentArea;

    _subscriptions[type]?.cancel();

    final stream = _repository.getPlatesByTypeAndArea(
      type,
      area,
    );

    final subscription = stream.listen((filteredData) {
      _data[type] = filteredData;
      notifyListeners();
    });

    _subscriptions[type] = subscription;
  }

  Future<void> updatePlateLocally(PlateType collection, PlateModel updatedPlate) async {
    final list = _data[collection];
    if (list == null) return;

    final index = list.indexWhere((p) => p.id == updatedPlate.id);
    if (index != -1) {
      _data[collection]![index] = updatedPlate;
      notifyListeners();
    }
  }

  Future<void> toggleIsSelected({
    required PlateType collection,
    required String plateNumber,
    required String userName,
    required void Function(String) onError,
  }) async {
    final plateId = '${plateNumber}_$currentArea';

    try {
      final plateList = _data[collection];
      if (plateList == null) {
        throw Exception('🚨 Collection not found: $collection');
      }

      final index = plateList.indexWhere((p) => p.id == plateId);
      if (index == -1) {
        final isCloned = RegExp(r'^\d{10,}_').hasMatch(plateId);
        final reason = isCloned ? '복제된 문서는 선택 기능을 지원하지 않습니다.' : '해당 문서가 데이터 목록에 없습니다.';
        throw Exception('🚨 다시 생성한 문서의 로그를 확인하세요.: $plateId\n$reason');
      }

      final plate = plateList[index];

      if (plate.isSelected && plate.selectedBy != userName) {
        throw Exception('⚠️ 이미 다른 사용자가 선택한 번호판입니다.');
      }

      final alreadySelected = _data.entries.expand((entry) => entry.value).firstWhere(
            (p) => p.isSelected && p.selectedBy == userName && p.id != plateId,
            orElse: () => PlateModel(
              id: '',
              plateNumber: '',
              plateFourDigit: '',
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

  Future<void> fetchPlateData() async {
    _initializeSubscriptions();
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

  PlateModel? getSelectedPlate(PlateType collection, String userName) {
    final plates = _data[collection];
    if (plates == null || plates.isEmpty) return null;

    return plates.firstWhere(
      (plate) => plate.isSelected && plate.selectedBy == userName,
      orElse: () => PlateModel(
        id: '',
        plateNumber: '',
        plateFourDigit: '',
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

  void syncWithAreaState() {
    debugPrint("🔄 PlateState: 지역 변경 감지 및 상태 갱신 호출됨");
    _previousArea = '';
    _initializeSubscriptions();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
