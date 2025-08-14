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

  /// 전이 추적용 (선택 사용)
  final Map<String, bool> previousIsLockedFee = {};

  /// 타입별 최신 데이터
  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: [],
  };

  /// 타입별 메인 스트림 구독
  final Map<PlateType, StreamSubscription> _subscriptions = {};

  /// 타입별 정렬 상태 (true: 내림차순)
  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  /// 타입별 구독 중인 지역
  final Map<PlateType, String> _subscribedAreas = {};

  bool _isLoading = false;

  /// 사용자가 구독을 원한 타입 (지역 변경시 재구독 대상)
  final Set<PlateType> _desiredSubscriptions = {};

  PlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged);
    _initDefaultSubscriptions(); // 기본: 입차 요청, 출차 요청, 출차 완료
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
      debugPrint('↺ [${_getTypeLabel(type)}] 지역 변경으로 재구독 준비 (이전: $existingArea → 현재: $area)');
    }

    debugPrint('🔔 [${_getTypeLabel(type)}] 구독 시작 (지역: $area)');
    _isLoading = true;
    notifyListeners();

    if (type == PlateType.departureCompleted) {
      final sub = _repository.departureUnpaidSnapshots(area, descending: descending).listen(
          (QuerySnapshot<Map<String, dynamic>> snapshot) async {
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

            final fresh = await ref.get(const GetOptions(source: Source.server));

            final data = fresh.data();
            if (data == null) continue;

            final isDepartureCompleted = data['type'] == PlateType.departureCompleted.firestoreValue;
            final sameArea = data['area'] == area;
            final isLockedFeeTrue = data['isLockedFee'] == true;

            if (isDepartureCompleted && sameArea && isLockedFeeTrue) {
              // ✅ 전이 확정(미정산 → 정산)
              debugPrint('✅ 정산 전이 감지: doc=${fresh.id}, plate=${data['plateNumber']}');

              // 선택: 로컬 추적 (중복 처리 방지 용도)
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

    // ▣ 그 외 타입은 기존처럼 모델 리스트 스트림 사용
    final stream = _repository.streamToCurrentArea(
      type,
      area,
      descending: descending,
    );

    bool firstDataReceived = false;

    final subscription = stream.listen((filteredData) async {
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
    _subscribedAreas[type] = area;
  }

  /// 타입별 구독 해제
  void unsubscribeType(PlateType type) {
    _desiredSubscriptions.remove(type);

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

  /// 타입별 데이터 조회(출차 완료는 로컬 날짜 필터 지원)
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

  /// 정렬 변경(실제 반영은 재구독 필요)
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

  /// 외부에서 강제 동기화(지역 변경 등)
  void syncWithAreaState() {
    debugPrint("🔄 syncWithAreaState : 지역 변경 감지 및 상태 갱신 호출됨");
    _cancelAllSubscriptions();
    for (final t in _desiredSubscriptions) {
      subscribeType(t);
    }
  }

  /// 앱 시작 시 기본 구독
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

  /// AreaState 지역 변경 시 재구독
  void _onAreaChanged() {
    debugPrint("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _cancelAllSubscriptions();
    for (final t in _desiredSubscriptions) {
      subscribeType(t);
    }
  }

  /// 모든 구독 취소
  void _cancelAllSubscriptions() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _subscribedAreas.clear();
    _isLoading = false;
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
    super.dispose();
  }
}
