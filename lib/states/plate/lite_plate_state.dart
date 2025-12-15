import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../repositories/plate_repo_services/plate_repository.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../area/area_state.dart';

// import '../../utils/usage_reporter.dart';

/// 서버 스냅샷 기준의 선택 상태를 plateId별로 보관하기 위한 베이스라인
class _SelectionBaseline {
  final bool isSelected;
  final String? selectedBy;

  const _SelectionBaseline({required this.isSelected, required this.selectedBy});
}

class LitePlateState extends ChangeNotifier {
  /// ✅ Lite 모드에서는 "입차 완료/출차 완료"만 사용(구독/데이터 대상 제한)
  static const Set<PlateType> liteAllowedTypes = {
    PlateType.parkingCompleted,   // 입차 완료
    PlateType.departureCompleted, // 출차 완료
  };

  final PlateRepository _repository;
  final AreaState _areaState;

  // ✅ 필드 페이지에서만 스트림을 켜기 위한 스위치 (HQ에서는 false 유지)
  bool _enabled = false;

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
  // departureRequests에서 "사라진" 항목 감지를 위한 캐시 & 이벤트
  // (Lite 모드에서는 departureRequests를 사용하지 않지만, 공용 코드 구조 유지)
  // ─────────────────────────────────────────────────────────────
  final Map<PlateType, Map<String, PlateModel>> _lastByType = {
    for (var c in PlateType.values) c: {},
  };

  final StreamController<PlateModel> _departureRemovedCtrl = StreamController<PlateModel>.broadcast();

  /// 출차요청 컬렉션에서 사라진 번호판(= 다른 타입으로 이동 추정) 이벤트 스트림
  Stream<PlateModel> get onDepartureRequestRemoved => _departureRemovedCtrl.stream;

  // ─────────────────────────────────────────────────────────────
  // ✅ 선택/해제 지연 반영을 위한 보류 상태
  // ─────────────────────────────────────────────────────────────
  PlateType? _pendingCollection;
  String? _pendingPlateId;
  bool? _pendingIsSelected;
  String? _pendingSelectedBy;

  /// 서버 기준 선택 상태 베이스라인 (plateId → 상태)
  final Map<String, _SelectionBaseline> _baseline = {};

  /// 현재 보류 중인(아직 서버에 반영하지 않은) 선택/해제 변경이 있는지
  bool get hasPendingSelection => _pendingCollection != null && _pendingPlateId != null && _pendingIsSelected != null;

  /// 현재 보류가 선택(true)인지 해제(false)인지, 보류 없으면 null
  bool? get pendingIsSelected => _pendingIsSelected;

  void _clearPendingSelection() {
    _pendingCollection = null;
    _pendingPlateId = null;
    _pendingIsSelected = null;
    _pendingSelectedBy = null;
  }

  /// 🔸 외부 동작(예: 정보 수정)으로 동일 plateId의 선택 의도가 무의미해졌을 때 호출
  void clearPendingSelection() {
    _clearPendingSelection();
    notifyListeners();
  }

  /// 🔸 특정 plateId와 일치할 때만 보류 선택을 해제
  void clearPendingIfMatches(String plateId) {
    if (_pendingPlateId == plateId) {
      _clearPendingSelection();
      notifyListeners();
    }
  }

  LitePlateState(this._repository, this._areaState) {
    // Lite 모드에서도 "완료 목록"은 지역에 따라 바뀌므로 area change 리스너는 유지
    _areaState.addListener(_onAreaChanged);
  }

  String get currentArea => _areaState.currentArea;

  bool get isLoading => _isLoading;

  List<PlateModel> dataOfType(PlateType type) => _data[type] ?? [];

  bool isSubscribed(PlateType type) => _desiredSubscriptions.contains(type);

  String? getSubscribedArea(PlateType type) => _subscribedAreas[type];

  // ─────────────────────────────────────────────────────────────
  // 공개 스위치: 필드 페이지에서만 구독 활성화/비활성화
  // ─────────────────────────────────────────────────────────────
  /// Lite 모드: withDefaults=true면 "입차완료/출차완료" 2종만 즉시 구독합니다.
  void enableForTypePages({bool withDefaults = true}) {
    if (_enabled) return;
    _enabled = true;
    debugPrint('🔔 [Lite] PlateState enabled (Completed only) / withDefaults=$withDefaults');

    if (withDefaults) {
      _initDefaultSubscriptions();
    }
  }

  void disableAll() {
    if (!_enabled && _subscriptions.isEmpty) return;
    _enabled = false;
    debugPrint('🔕 [Lite] PlateState disabled (leaving pages)');
    _cancelAllSubscriptions();
  }

  // ─────────────────────────────────────────────────────────────
  // 📱 태블릿 전용 헬퍼들 (Lite에서는 원칙적으로 사용하지 않음)
  // ─────────────────────────────────────────────────────────────

  void tabletEnableWithoutDefaults() {
    debugPrint('⚠️ [Lite] tabletEnableWithoutDefaults() called but Lite uses completed-only subscriptions');
    enableForTypePages(withDefaults: false);
  }

  void tabletSubscribeDeparture() {
    debugPrint('🚫 [Lite] tabletSubscribeDeparture ignored (Lite does not use departureRequests)');
  }

  void tabletUnsubscribeDeparture() {
    debugPrint('🚫 [Lite] tabletUnsubscribeDeparture ignored (Lite does not use departureRequests)');
  }

  // ─────────────────────────────────────────────────────────────

  void subscribeType(PlateType type) {
    // ✅ Lite 모드: 허용된 타입(입차완료/출차완료)만 구독
    if (!liteAllowedTypes.contains(type)) {
      debugPrint('🚫 [Lite] subscribeType ignored (not allowed): $type / area=$currentArea');
      return;
    }

    // ✅ 비활성 상태면 아무 것도 하지 않음
    if (!_enabled) {
      debugPrint('🔕 [Lite] PlateState disabled → subscribeType 무시: $type');
      return;
    }

    _desiredSubscriptions.add(type);

    final descending = _isSortedMap[type] ?? true;
    final area = currentArea;

    final existing = _subscriptions[type];
    final existingArea = _subscribedAreas[type];

    if (existing != null && existingArea == area) {
      debugPrint('✅ [Lite] 이미 구독 중(같은 지역): $type / $area');
      return;
    }

    if (existing != null && existingArea != area) {
      existing.cancel();
      _subscriptions.remove(type);
      _subscribedAreas.remove(type);
      debugPrint('↺ [Lite][${_getTypeLabel(type)}] 지역 변경으로 재구독 준비 (이전: $existingArea → 현재: $area)');
    }

    debugPrint('🔔 [Lite][${_getTypeLabel(type)}] 구독 시작 (지역: $area)');
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
            debugPrint('❌ [Lite] departureCompleted parsing error: $e');
            return null;
          }
        })
            .whereType<PlateModel>()
            .toList();

        // 서버 베이스라인 갱신 (해제 상태면 selectedBy를 null로 정규화)
        for (final p in results) {
          final normalizedSelectedBy = p.isSelected
              ? ((p.selectedBy?.trim().isNotEmpty ?? false) ? p.selectedBy!.trim() : null)
              : null;
          _baseline[p.id] = _SelectionBaseline(
            isSelected: p.isSelected,
            selectedBy: normalizedSelectedBy,
          );
        }

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
              debugPrint('✅ [Lite] 정산 전이 감지: doc=${fresh.id}, plate=${data['plateNumber']}');

              final key = (data['id'] ?? fresh.id).toString();
              previousIsLockedFee[key] = true;
            }
          } catch (e) {
            debugPrint('⚠️ [Lite][출차 완료 전이 감지] removed 처리 실패: $e');
          }
        }

        // ⬇️ 스트림 갱신 이후 보류 유효성 재점검
        if (hasPendingSelection && !pendingStillValidFor(type)) {
          _clearPendingSelection();
          notifyListeners();
          debugPrint('ℹ️ [Lite] 전환/필터/외부 변경으로 보류를 해제했습니다.');
        }

        _isLoading = false;
      }, onError: (error) {
        debugPrint('🔥 [Lite][출차 완료] 스냅샷 스트림 에러: $error');
        _isLoading = false;
        notifyListeners();
      });

      _subscriptions[type] = sub;
      _subscribedAreas[type] = area;
      return;
    }

    // ✅ parkingCompleted는 일반 스트림 경로 사용
    final stream = _repository.streamToCurrentArea(
      type,
      area,
      descending: descending,
    );

    bool firstDataReceived = false;

    final subscription = stream.listen((filteredData) async {
      // Lite 모드에서는 departureRequests를 구독하지 않으므로 below branch는 사실상 실행되지 않음
      if (type == PlateType.departureRequests) {
        final lastMap = _lastByType[type] ?? {};
        final currentMap = {for (final p in filteredData) p.id: p};

        for (final removedId in lastMap.keys.where((id) => !currentMap.containsKey(id))) {
          final removed = lastMap[removedId];
          if (removed != null) {
            _departureRemovedCtrl.add(removed);
          }
        }
        _lastByType[type] = currentMap;
      } else {
        _lastByType[type] = {for (final p in filteredData) p.id: p};
      }

      // 서버 베이스라인 갱신 (해제 상태면 selectedBy를 null로 정규화)
      for (final p in filteredData) {
        final normalizedSelectedBy = p.isSelected
            ? ((p.selectedBy?.trim().isNotEmpty ?? false) ? p.selectedBy!.trim() : null)
            : null;
        _baseline[p.id] = _SelectionBaseline(
          isSelected: p.isSelected,
          selectedBy: normalizedSelectedBy,
        );
      }

      _data[type] = filteredData;
      notifyListeners();

      if (hasPendingSelection && !pendingStillValidFor(type)) {
        _clearPendingSelection();
        notifyListeners();
        debugPrint('ℹ️ [Lite] 전환/필터/외부 변경으로 보류를 해제했습니다.');
      }

      if (!firstDataReceived) {
        firstDataReceived = true;
        debugPrint('✅ [Lite][${_getTypeLabel(type)}] 초기 데이터 수신: ${filteredData.length}개');
      } else {
        debugPrint('📥 [Lite][${_getTypeLabel(type)}] 데이터 업데이트: ${filteredData.length}개');
      }

      _isLoading = false;
    }, onError: (error) {
      debugPrint('🔥 [Lite][${_getTypeLabel(type)}] Plate stream error: $error');
      _isLoading = false;
      notifyListeners();
    });

    _subscriptions[type] = subscription;
    _subscribedAreas[type] = area;
  }

  void unsubscribeType(PlateType type) {
    // ✅ Lite 모드: 허용 타입 외 unsubscribe도 무시(안전)
    if (!liteAllowedTypes.contains(type)) {
      debugPrint('🚫 [Lite] unsubscribeType ignored (not allowed): $type');
      return;
    }

    _desiredSubscriptions.remove(type);

    final sub = _subscriptions[type];
    final area = _subscribedAreas[type];

    if (sub != null) {
      sub.cancel();
      _subscriptions.remove(type);
      _subscribedAreas.remove(type);
      _data[type] = [];
      _lastByType[type] = {};
      notifyListeners();
      debugPrint('🛑 [Lite][${_getTypeLabel(type)}] 구독 해제됨 (지역: $area)');
    } else {
      debugPrint('⚠️ [Lite][${_getTypeLabel(type)}] 구독 중이 아님');
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

  /// ✅ 선택/해제 시 로컬 토글 + 보류 기록
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
        onError(
          '⚠️ 이미 다른 번호판을 선택한 상태입니다.\n'
              '• 선택된 번호판: ${alreadySelected.plateNumber}\n'
              '선택을 해제한 후 다시 시도해 주세요.',
        );
        return;
      }

      if (_pendingPlateId != null && _pendingPlateId != plateId) {
        final prevId = _pendingPlateId!;
        final prevType = _pendingCollection!;
        final prevList = _data[prevType];
        final b = _baseline[prevId];
        if (prevList != null && b != null) {
          final i = prevList.indexWhere((p) => p.id == prevId);
          if (i != -1) {
            prevList[i] = prevList[i].copyWith(
              isSelected: b.isSelected,
              selectedBy: b.selectedBy,
            );
          }
        }
        _clearPendingSelection();
      }

      final newIsSelected = !plate.isSelected;
      final newSelectedBy = newIsSelected ? userName : null;

      _data[collection]![index] = plate.copyWith(
        isSelected: newIsSelected,
        selectedBy: newSelectedBy,
      );

      final base = _baseline[plateId];
      bool equalsBaseline = false;
      if (base != null) {
        if (!newIsSelected && base.isSelected == false) {
          equalsBaseline = true;
        } else {
          final baseSelBy = (base.selectedBy ?? '').trim();
          final newSelBy = (newSelectedBy ?? '').trim();
          equalsBaseline = (base.isSelected == newIsSelected) && (baseSelBy == newSelBy);
        }
      }

      if (equalsBaseline) {
        if (_pendingPlateId == plateId) {
          _clearPendingSelection();
        }
      } else {
        _pendingCollection = collection;
        _pendingPlateId = plateId;
        _pendingIsSelected = newIsSelected;
        _pendingSelectedBy = newSelectedBy;
      }

      notifyListeners();
    } catch (e) {
      onError('🚨 번호판 선택 상태 변경 실패:\n$e');
    }
  }

  bool pendingStillValidFor(PlateType expected) {
    if (!hasPendingSelection) return false;
    if (_pendingCollection != expected) return false;

    final list = _data[expected];
    if (list == null) return false;

    final id = _pendingPlateId!;
    PlateModel? p;
    try {
      p = list.firstWhere((e) => e.id == id);
    } catch (_) {
      p = null;
    }
    if (p == null) return false;

    final base = _baseline[id];
    final pendSel = _pendingIsSelected!;
    final pendBy = _pendingSelectedBy;

    if (base != null) {
      if (!pendSel && base.isSelected == false) {
        return false;
      } else if (pendSel && base.isSelected == true) {
        final baseSelBy = (base.selectedBy ?? '').trim();
        final pendByNorm = (pendBy ?? '').trim();
        if (baseSelBy == pendByNorm) {
          return false;
        }
      }
    }

    if (pendSel &&
        p.isSelected == false &&
        p.selectedBy == null &&
        base != null &&
        base.isSelected == false &&
        base.selectedBy == null) {
      return false;
    }

    return true;
  }

  Future<void> commitPendingSelection({
    required void Function(String) onError,
  }) async {
    if (!hasPendingSelection) return;

    final plateId = _pendingPlateId!;
    final isSelected = _pendingIsSelected!;
    final selectedBy = _pendingSelectedBy;
    final expected = _pendingCollection!;

    if (!pendingStillValidFor(expected)) {
      _clearPendingSelection();
      notifyListeners();
      onError('선택 항목이 더 이상 유효하지 않습니다. 목록을 새로고침한 뒤 다시 시도해 주세요.');
      return;
    }

    try {
      await _repository.recordWhoPlateClick(
        plateId,
        isSelected,
        selectedBy: selectedBy,
        area: currentArea,
      );

      _baseline[plateId] = _SelectionBaseline(
        isSelected: isSelected,
        selectedBy: isSelected
            ? ((selectedBy?.trim().isNotEmpty ?? false) ? selectedBy!.trim() : null)
            : null,
      );

      _clearPendingSelection();
      notifyListeners();
    } on FirebaseException catch (e) {
      switch (e.code) {
        case 'invalid-state':
          onError('이미 다른 상태로 처리된 문서입니다. 목록을 새로고침해 주세요.');
          break;
        case 'conflict':
          onError('다른 사용자가 먼저 선택했습니다.');
          break;
        case 'not-found':
          onError('문서를 찾을 수 없습니다.');
          break;
        default:
          onError('DB 오류: ${e.message ?? e.code}');
      }
    } catch (e) {
      onError('🚨 번호판 변경 사항 반영 실패:\n$e');
    }
  }

  List<PlateModel> getPlatesByCollection(PlateType collection, {DateTime? selectedDate}) {
    var plates = _data[collection] ?? [];

    if (collection == PlateType.departureCompleted && selectedDate != null) {
      final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
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
    if (!_enabled) {
      debugPrint("🔕 [Lite] PlateState disabled → syncWithAreaState 무시");
      return;
    }

    final desired = _desiredSubscriptions.toSet();
    final subscribedTypes = _subscriptions.keys.toSet();
    final sameTypes = desired.length == subscribedTypes.length && desired.containsAll(subscribedTypes);
    final sameAreaAll = _subscribedAreas.values.every((a) => a == currentArea);
    if (sameTypes && sameAreaAll) {
      debugPrint("ℹ️ [Lite] syncWithAreaState: 동일 구성/지역 → 재구독 생략");
      return;
    }

    debugPrint("🔄 [Lite] syncWithAreaState : 지역 변경 감지 및 상태 갱신 호출됨");
    _cancelAllSubscriptions();
    _clearPendingSelection();
    _baseline.clear();
    for (final t in _desiredSubscriptions) {
      subscribeType(t);
    }
  }

  void _initDefaultSubscriptions() {
    // ✅ Lite 기본 구독: 입차 완료 + 출차 완료만
    final defaults = <PlateType>[
      PlateType.parkingCompleted,
      PlateType.departureCompleted,
    ];
    for (final t in defaults) {
      subscribeType(t);
    }
  }

  void _onAreaChanged() {
    if (!_enabled) {
      debugPrint("🔕 [Lite] PlateState disabled → _onAreaChanged 무시");
      return;
    }
    debugPrint("🔄 [Lite] 지역 변경 감지됨: ${_areaState.currentArea}");
    _cancelAllSubscriptions();
    _clearPendingSelection();
    _baseline.clear();
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
    _departureRemovedCtrl.close();
    super.dispose();
  }
}
