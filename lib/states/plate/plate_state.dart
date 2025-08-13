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

  // 이전 isLockedFee 상태 저장 (요약 로그 생성 트리거 용)
  final Map<String, bool> previousIsLockedFee = {};

  // 타입별 데이터 캐시
  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: [],
  };

  // 타입별 구독 핸들
  final Map<PlateType, StreamSubscription<List<PlateModel>>> _subscriptions = {};

  // 타입별 정렬 상태 (기본: 내림차순)
  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  // 타입별 구독 지역 저장
  final Map<PlateType, String> _subscribedAreas = {};

  // (유지: 외부 의존 코드 고려해 필드/게터는 보존하되 내부 필터에는 사용하지 않음)
  String? _searchQuery;

  bool _isLoading = false;

  PlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged);
  }

  // 외부 참조용 (유지)
  String get searchQuery => _searchQuery ?? "";

  // 현재 지역
  String get currentArea => _areaState.currentArea;

  bool get isLoading => _isLoading;

  // 타입별 원시 데이터 조회
  List<PlateModel> dataOfType(PlateType type) => _data[type] ?? [];

  // 구독 여부
  bool isSubscribed(PlateType type) => _subscriptions.containsKey(type);

  // 구독 지역 조회
  String? getSubscribedArea(PlateType type) => _subscribedAreas[type];

  // 타입 구독 시작
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
      // 출차 완료: isLockedFee 변경 감지 시 요약 로그 생성
      if (type == PlateType.departureCompleted) {
        for (final plate in filteredData) {
          final previous = previousIsLockedFee[plate.id];
          if (previous == false && plate.isLockedFee == true) {
            final uploader = GcsJsonUploader();
            await uploader.generateSummaryLog(
              plateNumber: plate.plateNumber,
              division: _areaState.currentDivision,
              area: plate.area,
              date: DateTime.now(),
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
    _subscribedAreas[type] = area; // 구독 지역 저장
  }

  // 타입 구독 해제
  void unsubscribeType(PlateType type) {
    final sub = _subscriptions[type];
    final area = _subscribedAreas[type];

    if (sub != null) {
      sub.cancel();
      _subscriptions.remove(type);
      _subscribedAreas.remove(type);
      _data[type] = [];
      notifyListeners();
      debugPrint('🛑 [${_getTypeLabel(type)}] 구독 해제됨 (지역: $area)');
    } else {
      debugPrint('⚠️ [${_getTypeLabel(type)}] 구독 중이 아님');
    }
  }

  // 사용자 기준 선택된 Plate 조회
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

  // 선택 토글
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

      // 동일 사용자에 의해 이미 다른 Plate 선택 중인지 확인
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
    var plates = _data[collection] ?? [];

    if (collection == PlateType.departureCompleted && selectedDate != null) {
      final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      final end = start.add(const Duration(days: 1));

      plates = plates.where((p) {
        // endTime 없으면 updatedAt → requestTime 순으로 대체
        final t = p.endTime ?? p.updatedAt ?? p.requestTime;
        return !t.isBefore(start) && t.isBefore(end);
      }).toList();
    }

    return plates;
  }

  // 정렬 방향 변경 (필요 시 스트림 쿼리 재구독 로직을 함께 넣는 것을 고려)
  void updateSortOrder(PlateType type, bool descending) {
    _isSortedMap[type] = descending;
    notifyListeners();
  }

  // 로컬 캐시 업데이트
  Future<void> updatePlateLocally(PlateType collection, PlateModel updatedPlate) async {
    final list = _data[collection];
    if (list == null) return;

    final index = list.indexWhere((p) => p.id == updatedPlate.id);
    if (index != -1) {
      _data[collection]![index] = updatedPlate;
      notifyListeners();
    }
  }

  // AreaState와 동기화(외부 호출용)
  void syncWithAreaState() {
    debugPrint("🔄 syncWithAreaState : 지역 변경 감지 및 상태 갱신 호출됨");
    _cancelAllSubscriptions();
  }

  // AreaState 변경 리스너
  void _onAreaChanged() {
    debugPrint("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _cancelAllSubscriptions();
  }

  // 전체 구독 취소 및 상태 초기화
  void _cancelAllSubscriptions() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _subscribedAreas.clear();
  }

  // 타입 라벨
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
