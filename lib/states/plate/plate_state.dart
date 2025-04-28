import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../area/area_state.dart';
import '../../enums/plate_type.dart';
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

  final Map<PlateType, DateTime?> _lastFetchedAt = {
    for (var c in PlateType.values) c: null,
  };

  String? _searchQuery;
  String _previousArea = '';

  bool _isLoading = true;

  bool get isLoading => _isLoading;

  String get searchQuery => _searchQuery ?? "";

  String get currentArea => _areaState.currentArea;

  final Map<String, bool> previousIsLockedFee = {};

  void _initializeSubscriptions() {
    final area = _areaState.currentArea;
    if (area.isEmpty || _previousArea == area) return;

    _previousArea = area;
    _cancelAllSubscriptions();

    _isLoading = true;
    plateCounts();

    int receivedCount = 0;
    final totalCollections = PlateType.values.length;

    for (final collection in PlateType.values) {
      if (collection == PlateType.parkingCompleted) {
        fetchPlatesByTypeAndArea(collection).then((_) {
          receivedCount++;
          if (receivedCount == totalCollections) {
            _isLoading = false;
            plateCounts();
          }
        }).catchError((error) {
          debugPrint('🔥 Plate fetch error (parkingCompleted): $error');
        });
      } else {
        final stream = _repository.getPlatesByTypeAndArea(collection, area);

        bool firstDataReceived = false;

        final subscription = stream.listen((filteredData) async {
          if (collection == PlateType.departureCompleted) {
            for (final plate in filteredData) {
              final previous = previousIsLockedFee[plate.id];

              if (previous == false && plate.isLockedFee == true) {
                final uploader = GCSUploader();
                await uploader.mergeAndReplaceLogs(
                  plate.plateNumber,
                  _areaState.currentDivision,
                  plate.area,
                );
              }

              previousIsLockedFee[plate.id] = plate.isLockedFee;
            }
          }

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
        }, onError: (error) {
          debugPrint('🔥 Plate stream error: $error');
        });

        _subscriptions[collection] = subscription;
      }
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
      plates = plates.where((plate) {
        final last4Digits = plate.plateNumber.length >= 4
            ? plate.plateNumber.substring(plate.plateNumber.length - 4)
            : plate.plateNumber;
        return last4Digits == _searchQuery;
      }).toList();
    }

    return plates;
  }

  Future<int> countParkingCompletedPlates() async {
    try {
      final area = _areaState.currentArea;
      if (area.isEmpty) {
        debugPrint('🚨 지역 정보 없음');
        return 0;
      }

      final count = await _repository.getPlateCountByType(
        PlateType.parkingCompleted,
        selectedDate: null, // 날짜 필터 없음
      );

      debugPrint('✅ 현재 입차 완료 plates 수: $count');
      return count;
    } catch (e, s) {
      debugPrint('🔥 입차 완료 plates count 실패: $e');
      debugPrintStack(stackTrace: s);
      return 0;
    }
  }

  Future<void> fetchPlatesByTypeAndArea(PlateType type) async {
    try {
      final area = _areaState.currentArea;
      if (area.isEmpty) return;

      final fetchedData = await _repository.fetchPlatesByTypeAndArea(type, area);

      // ✅ 새로 받아온 plates의 id Set
      final fetchedIds = fetchedData.map((p) => p.id).toSet();

      // ✅ 기존 local plates
      final existingPlates = _data[type] ?? [];

      // ✅ 삭제 감지: 기존 plates 중 서버에 없는 plates 제거
      final mergedPlates = existingPlates
          .where((plate) => fetchedIds.contains(plate.id)) // 살아남은 plates
          .toList();

      // ✅ 새 plates를 id 기준으로 덮어쓰기 (merge)
      final plateMap = {for (var plate in mergedPlates) plate.id: plate};
      for (final newPlate in fetchedData) {
        plateMap[newPlate.id] = newPlate; // 🔥 새로운 plates 추가/갱신
      }

      // ✅ 정렬: request_time 기준 최신순
      final updatedPlates = plateMap.values.toList()..sort((a, b) => b.requestTime.compareTo(a.requestTime));

      // ✅ 가장 최신 updatedAt 계산
      final latestUpdatedAt = updatedPlates.isNotEmpty
          ? updatedPlates.map((p) => p.updatedAt ?? DateTime(2000)).reduce((a, b) => a.isAfter(b) ? a : b)
          : DateTime(2000);

      _data[type] = updatedPlates;
      _lastFetchedAt[type] = latestUpdatedAt;
      notifyListeners();

      debugPrint('🔄 $type: plates ${fetchedData.length}개 증분 merge + 삭제 감지 완료');
    } catch (e, s) {
      debugPrint('🔥 Error during incremental fetch with delete detection: $e');
      debugPrintStack(stackTrace: s);
    }
  }

  /// ✅ 입차 완료 plates 수를 비교 후 필요 시 fetch하는 메서드
  Future<void> fetchParkingCompletedIfChanged() async {
    try {
      final area = _areaState.currentArea;
      if (area.isEmpty) {
        debugPrint('🚨 지역 정보 없음');
        return;
      }

      final localPlates = _data[PlateType.parkingCompleted] ?? [];
      final localCount = localPlates.length;

      final serverCount = await countParkingCompletedPlates(); // 서버 count 조회

      if (serverCount != localCount) {
        debugPrint('🔄 변화 감지: local($localCount) vs server($serverCount), fetch 실행');
        await fetchPlatesByTypeAndArea(PlateType.parkingCompleted);
      } else {
        debugPrint('✅ 변화 없음: fetch 생략');
      }
    } catch (e, s) {
      debugPrint('🔥 fetchParkingCompletedIfChanged 실패: $e');
      debugPrintStack(stackTrace: s);
    }
  }
  Future<void> fetchPlateData() async {
    debugPrint('🔄 새로고침 요청: plates 최신 상태 확인 중');
    for (final type in PlateType.values) {
      await fetchPlatesByTypeAndArea(type);
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

      debugPrint('🔎 Trying to select plateId: $plateId');
      debugPrint('📋 Plates in collection $collection: ${plateList.map((p) => p.id).toList()}');

      final index = plateList.indexWhere((p) => p.id == plateId);
      if (index == -1) {
        throw Exception('🚨 Plate not found in collection $collection: $plateId');
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

  Future<void> updatePlateLocally(PlateType collection, PlateModel updatedPlate) async {
    final list = _data[collection];
    if (list == null) return;

    final index = list.indexWhere((p) => p.id == updatedPlate.id);
    if (index != -1) {
      _data[collection]![index] = updatedPlate;
      notifyListeners();
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

  PlateModel? getSelectedPlate(PlateType collection, String userName) {
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

  void syncWithAreaState() {
    debugPrint("🔄 PlateState: 지역 변경 감지 및 상태 갱신 호출됨");
    _initializeSubscriptions();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
