import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../utils/gcs_json_uploader.dart';
import '../area/area_state.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;
  final Map<String, bool> previousIsLockedFee = {};
  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: [],
  };
  final Map<PlateType, StreamSubscription<List<PlateModel>>> _subscriptions = {};
  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  final Map<PlateType, String> _subscribedAreas = {}; // ✅ 구독된 지역 저장

  String? _searchQuery;
  bool _isLoading = false;

  PlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged);
  }

  String get searchQuery => _searchQuery ?? "";

  String get currentArea => _areaState.currentArea;

  bool get isLoading => _isLoading;

  List<PlateModel> dataOfType(PlateType type) => _data[type] ?? [];

  bool isSubscribed(PlateType type) => _subscriptions.containsKey(type);

  String? getSubscribedArea(PlateType type) => _subscribedAreas[type]; // ✅ 추가

  void subscribeType(PlateType type) {
    if (_subscriptions.containsKey(type)) {
      debugPrint('✅ 이미 구독 중: $type');
      return;
    }

    final descending = _isSortedMap[type] ?? true;
    final area = currentArea;

    debugPrint('🔔 [${_getTypeLabel(type)}] 구독 시작 (지역: $area)');
    _isLoading = true;
    notifyListeners();

    final stream = _repository.streamToCurrentArea(
      type,
      area,
      descending: descending,
    );

    bool firstDataReceived = false;

    final subscription = stream.listen((filteredData) async {
      if (type == PlateType.departureCompleted) {
        for (final plate in filteredData) {
          final previous = previousIsLockedFee[plate.id];
          if (previous == false && plate.isLockedFee == true) {
            final uploader = GcsJsonUploader();
            await uploader.mergeAndSummarizeLogs(
              plate.plateNumber,
              _areaState.currentDivision,
              plate.area,
            );
          }
          previousIsLockedFee[plate.id] = plate.isLockedFee;
        }
      }

      _data[type] = filteredData;
      notifyListeners();

      if (!firstDataReceived) {
        firstDataReceived = true;
        debugPrint('✅ [${_getTypeLabel(type)}] 초기 데이터 수신: ${filteredData.length}개');
      } else {
        debugPrint('📥 [${_getTypeLabel(type)}] 데이터 업데이트: ${filteredData.length}개');
      }

      _isLoading = false;
    }, onError: (error) {
      debugPrint('🔥 [${_getTypeLabel(type)}] Plate stream error: $error');
      _isLoading = false;
      notifyListeners();
    });

    _subscriptions[type] = subscription;
    _subscribedAreas[type] = area; // ✅ 구독 지역 저장
  }

  void unsubscribeType(PlateType type) {
    final sub = _subscriptions[type];
    final area = _subscribedAreas[type];

    if (sub != null) {
      sub.cancel();
      _subscriptions.remove(type);
      _subscribedAreas.remove(type); // ✅ 제거
      _data[type] = [];
      notifyListeners();
      debugPrint('🛑 [${_getTypeLabel(type)}] 구독 해제됨 (지역: $area)');
    } else {
      debugPrint('⚠️ [${_getTypeLabel(type)}] 구독 중이 아님');
    }
  }

  PlateModel? getSelectedPlate(PlateType collection, String userName) {
    final plates = _data[collection];
    if (plates == null || plates.isEmpty) return null;

    try {
      return plates.firstWhere(
        (plate) => plate.isSelected && plate.selectedBy == userName,
      );
    } catch (_) {
      return null;
    }
  }

  // ✅ 수정: PlateType을 파라미터로 받도록 변경
  String _getCollectionLabelForType(PlateType type) {
    switch (type) {
      case PlateType.parkingRequests:
        return '입차 요청';
      case PlateType.parkingCompleted:
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료';
    }
  }

  Future<void> togglePlateIsSelected({
    required PlateType collection,
    required String plateNumber,
    required String userName,
    required void Function(String) onError,
  }) async {
    final plateId = '${plateNumber}_$currentArea';

    try {
      final plateList = _data[collection];
      if (plateList == null) {
        onError('🚨 선택할 수 있는 번호판 리스트가 없습니다.');
        return;
      }

      final index = plateList.indexWhere((p) => p.id == plateId);
      if (index == -1) {
        onError('🚨 선택할 수 있는 번호판이 없습니다.');
        return;
      }

      final plate = plateList[index];

      if (plate.isSelected && plate.selectedBy != userName) {
        onError('⚠️ 이미 다른 사용자(${plate.selectedBy})가 선택한 번호판입니다.');
        return;
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
        String collectionLabel = '알 수 없음';

        try {
          final typeEnum = PlateType.values.firstWhere(
            (e) => e.name == alreadySelected.type,
          );
          collectionLabel = _getCollectionLabelForType(typeEnum);
        } catch (_) {
          // enum 변환 실패 시 '알 수 없음' 유지
        }

        onError(
          '⚠️ 이미 다른 번호판을 선택한 상태입니다.\n'
          '• 선택된 번호판: ${alreadySelected.plateNumber}\n'
          '선택을 해제한 후 다시 시도해 주세요.',
        );
        return;
      }

      final newIsSelected = !plate.isSelected;
      final newSelectedBy = newIsSelected ? userName : null;

      await _repository.recordWhoPlateClick(
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
      onError('🚨 번호판 선택 상태 변경 실패:\n$e');
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
    notifyListeners();
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

  void syncWithAreaState() {
    debugPrint("🔄 syncWithAreaState : 지역 변경 감지 및 상태 갱신 호출됨");
    _cancelAllSubscriptions();
  }

  void _onAreaChanged() {
    debugPrint("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _cancelAllSubscriptions();
  }

  void _cancelAllSubscriptions() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _subscribedAreas.clear(); // ✅ 함께 초기화
  }

  String _getTypeLabel(PlateType type) {
    switch (type) {
      case PlateType.parkingRequests:
        return '입차 요청';
      case PlateType.parkingCompleted:
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료';
    }
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
