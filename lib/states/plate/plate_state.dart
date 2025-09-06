import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../area/area_state.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;

  final Map<String, bool> previousIsLockedFee = {};

  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: [],
  };

  final Map<PlateType, StreamSubscription> _subscriptions = {};

  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  final Map<PlateType, String> _subscribedAreas = {};

  bool _isLoading = false;

  final Set<PlateType> _desiredSubscriptions = {};

  // ─────────────────────────────────────────────────────────────
  // (추가) departureRequests에서 "사라진" 항목 감지를 위한 캐시 & 이벤트
  // ─────────────────────────────────────────────────────────────
  final Map<PlateType, Map<String, PlateModel>> _lastByType = {
    for (var c in PlateType.values) c: {},
  };

  final StreamController<PlateModel> _departureRemovedCtrl =
  StreamController<PlateModel>.broadcast();

  /// 출차요청 컬렉션에서 사라진 번호판(= 다른 타입으로 이동 추정) 이벤트 스트림
  Stream<PlateModel> get onDepartureRequestRemoved =>
      _departureRemovedCtrl.stream;

  PlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged);
    _initDefaultSubscriptions();
  }

  String get currentArea => _areaState.currentArea;

  bool get isLoading => _isLoading;

  List<PlateModel> dataOfType(PlateType type) => _data[type] ?? [];

  bool isSubscribed(PlateType type) => _desiredSubscriptions.contains(type);

  String? getSubscribedArea(PlateType type) => _subscribedAreas[type];

  void subscribeType(PlateType type) {
    _desiredSubscriptions.add(type);

    final descending = _isSortedMap[type] ?? true;
    final area = currentArea;

    final existing = _subscriptions[type];
    final existingArea = _subscribedAreas[type];

    if (existing != null && existingArea == area) {
      debugPrint('✅ 이미 구독 중(같은 지역): $type / $area');
      return;
    }

    if (existing != null && existingArea != area) {
      existing.cancel();
      _subscriptions.remove(type);
      _subscribedAreas.remove(type);
      debugPrint(
          '↺ [${_getTypeLabel(type)}] 지역 변경으로 재구독 준비 (이전: $existingArea → 현재: $area)');
    }

    debugPrint('🔔 [${_getTypeLabel(type)}] 구독 시작 (지역: $area)');
    _isLoading = true;
    notifyListeners();

    if (type == PlateType.departureCompleted) {
      final sub = _repository
          .departureUnpaidSnapshots(area, descending: descending)
          .listen((QuerySnapshot<Map<String, dynamic>> snapshot) async {
        final results = snapshot.docs
            .map((doc) {
          try {
            return PlateModel.fromDocument(doc);
          } catch (e) {
            debugPrint('❌ departureCompleted parsing error: $e');
            return null;
          }
        })
            .whereType<PlateModel>()
            .toList();
        _data[type] = results;
        notifyListeners();

        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.removed) continue;
          try {
            final ref = change.doc.reference;

            final fresh =
            await ref.get(const GetOptions(source: Source.server));

            final data = fresh.data();
            if (data == null) continue;

            final isDepartureCompleted =
                data['type'] == PlateType.departureCompleted.firestoreValue;
            final sameArea = data['area'] == area;
            final isLockedFeeTrue = data['isLockedFee'] == true;

            if (isDepartureCompleted && sameArea && isLockedFeeTrue) {
              debugPrint(
                  '✅ 정산 전이 감지: doc=${fresh.id}, plate=${data['plateNumber']}');

              final key = (data['id'] ?? fresh.id).toString();
              previousIsLockedFee[key] = true;
            }
          } catch (e) {
            debugPrint('⚠️ [출차 완료 전이 감지] removed 처리 실패: $e');
          }
        }

        _isLoading = false;
      }, onError: (error) {
        debugPrint('🔥 [출차 완료] 스냅샷 스트림 에러: $error');
        _isLoading = false;
        notifyListeners();
      });

      _subscriptions[type] = sub;
      _subscribedAreas[type] = area;
      return;
    }

    final stream = _repository.streamToCurrentArea(
      type,
      area,
      descending: descending,
    );

    bool firstDataReceived = false;

    final subscription = stream.listen((filteredData) async {
      // ─────────────────────────────────────────────────────────
      // (추가) departureRequests에 대해 "사라진 항목" 감지 → 1회 이벤트 발행
      // ─────────────────────────────────────────────────────────
      if (type == PlateType.departureRequests) {
        final lastMap = _lastByType[type] ?? {};
        final currentMap = {for (final p in filteredData) p.id: p};

        // last - current = 사라진 문서들
        for (final removedId
        in lastMap.keys.where((id) => !currentMap.containsKey(id))) {
          final removed = lastMap[removedId];
          if (removed != null) {
            _departureRemovedCtrl.add(removed);
          }
        }

        // 캐시 갱신
        _lastByType[type] = currentMap;
      } else {
        // 다른 타입은 캐시만 갱신(필요 시 확장 가능)
        _lastByType[type] = {for (final p in filteredData) p.id: p};
      }
      // ─────────────────────────────────────────────────────────

      _data[type] = filteredData;
      notifyListeners();

      if (!firstDataReceived) {
        firstDataReceived = true;
        debugPrint(
            '✅ [${_getTypeLabel(type)}] 초기 데이터 수신: ${filteredData.length}개');
      } else {
        debugPrint(
            '📥 [${_getTypeLabel(type)}] 데이터 업데이트: ${filteredData.length}개');
      }

      _isLoading = false;
    }, onError: (error) {
      debugPrint('🔥 [${_getTypeLabel(type)}] Plate stream error: $error');
      _isLoading = false;
      notifyListeners();
    });

    _subscriptions[type] = subscription;
    _subscribedAreas[type] = area;
  }

  void unsubscribeType(PlateType type) {
    _desiredSubscriptions.remove(type);

    final sub = _subscriptions[type];
    final area = _subscribedAreas[type];

    if (sub != null) {
      sub.cancel();
      _subscriptions.remove(type);
      _subscribedAreas.remove(type);
      _data[type] = [];
      _lastByType[type] = {}; // 캐시도 초기화
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

      final alreadySelected =
      _data.entries.expand((entry) => entry.value).firstWhere(
            (p) =>
        p.isSelected &&
            p.selectedBy == userName &&
            p.id != plateId,
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

  List<PlateModel> getPlatesByCollection(PlateType collection,
      {DateTime? selectedDate}) {
    var plates = _data[collection] ?? [];

    if (collection == PlateType.departureCompleted && selectedDate != null) {
      final start = DateTime(
          selectedDate.year, selectedDate.month, selectedDate.day);
      final end = start.add(const Duration(days: 1));

      plates = plates.where((p) {
        final t = p.endTime ?? p.updatedAt ?? p.requestTime;
        return !t.isBefore(start) && t.isBefore(end);
      }).toList();
    }

    return plates;
  }

  void updateSortOrder(PlateType type, bool descending) {
    _isSortedMap[type] = descending;
    notifyListeners();
  }

  Future<void> updatePlateLocally(
      PlateType collection, PlateModel updatedPlate) async {
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
    for (final t in _desiredSubscriptions) {
      subscribeType(t);
    }
  }

  void _initDefaultSubscriptions() {
    final defaults = <PlateType>[
      PlateType.parkingRequests,
      PlateType.departureRequests,
      PlateType.departureCompleted,
    ];
    for (final t in defaults) {
      subscribeType(t);
    }
  }

  void _onAreaChanged() {
    debugPrint("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _cancelAllSubscriptions();
    for (final t in _desiredSubscriptions) {
      subscribeType(t);
    }
  }

  void _cancelAllSubscriptions() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _subscribedAreas.clear();
    _isLoading = false;

    // 캐시 초기화
    for (final k in _lastByType.keys) {
      _lastByType[k] = {};
    }

    notifyListeners();
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
    _departureRemovedCtrl.close(); // 이벤트 스트림 종료
    super.dispose();
  }
}
