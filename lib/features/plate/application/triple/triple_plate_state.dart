import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../dev/application/area_state.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_model.dart';
import '../../domain/repositories/plate_repository.dart';

class _TripleSelectionBaseline {
  final bool isSelected;
  final String? selectedBy;

  const _TripleSelectionBaseline(
      {required this.isSelected, required this.selectedBy});
}

class TriplePlateState extends ChangeNotifier {
  static const Set<PlateType> tripleAllowedTypes = {
    PlateType.parkingCompleted,
    PlateType.departureCompleted,
  };

  final PlateRepository _repository;
  final AreaState _areaState;

  bool _enabled = false;

  final Set<PlateType> _loadingTypes = <PlateType>{};

  bool get isLoading => _loadingTypes.isNotEmpty;

  bool isLoadingType(PlateType type) => _loadingTypes.contains(type);

  final Map<PlateType, DateTime?> _lastTripleRefreshAtByType = {
    for (final t in PlateType.values) t: null,
  };
  final Map<PlateType, String> _lastTripleRefreshSourceByType = {
    for (final t in PlateType.values) t: '-',
  };

  DateTime? tripleLastRefreshAtOf(PlateType type) =>
      _lastTripleRefreshAtByType[type];

  String tripleLastRefreshSourceLabelOf(PlateType type) =>
      _lastTripleRefreshSourceByType[type] ?? '-';

  final Map<String, bool> previousIsLockedFee = <String, bool>{};

  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: <PlateModel>[],
  };

  List<PlateModel> dataOfType(PlateType type) => _data[type] ?? <PlateModel>[];

  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  final Set<PlateType> _activeTypes = <PlateType>{};

  final Map<PlateType, Set<String>> _lastIdsByType = {
    for (var c in PlateType.values) c: <String>{},
  };

  final Map<String, _TripleSelectionBaseline> _baseline =
      <String, _TripleSelectionBaseline>{};

  PlateType? _pendingCollection;
  String? _pendingPlateId;
  bool? _pendingIsSelected;
  String? _pendingSelectedBy;

  bool get hasPendingSelection =>
      _pendingCollection != null &&
      _pendingPlateId != null &&
      _pendingIsSelected != null;

  int _lifecycleEpoch = 0;

  final Map<PlateType, int> _reqSeqByType = {
    for (var c in PlateType.values) c: 0,
  };

  TriplePlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged);
  }

  String get currentArea => _areaState.currentArea;

  void _clearPendingSelectionInternal() {
    _pendingCollection = null;
    _pendingPlateId = null;
    _pendingIsSelected = null;
    _pendingSelectedBy = null;
  }

  void tripleEnableForTypePages({bool withDefaults = true}) {
    if (_enabled) return;
    _enabled = true;

    debugPrint(
        '🔔 [Triple] TriplePlateState enabled (NO-SUBSCRIBE) / withDefaults=$withDefaults');

    if (withDefaults) {
      _initDefaultLoads();
    }
  }

  void tripleDisableAll() {
    if (!_enabled && _activeTypes.isEmpty) return;

    _enabled = false;
    _lifecycleEpoch++;
    debugPrint('🔕 [Triple] TriplePlateState disabled (NO-SUBSCRIBE)');

    _activeTypes.clear();
    _baseline.clear();
    _clearPendingSelectionInternal();

    for (final t in PlateType.values) {
      _data[t] = <PlateModel>[];
      _lastIdsByType[t] = <String>{};
      _reqSeqByType[t] = 0;
      _lastTripleRefreshAtByType[t] = null;
      _lastTripleRefreshSourceByType[t] = '-';
    }

    _loadingTypes.clear();
    notifyListeners();
  }

  void tripleSubscribeType(PlateType type) {
    if (!tripleAllowedTypes.contains(type)) {
      debugPrint('🚫 [Triple] subscribeType ignored (not allowed): $type');
      return;
    }
    if (!_enabled) {
      debugPrint('🔕 [Triple] disabled → subscribeType ignored: $type');
      return;
    }

    _activeTypes.add(type);

    unawaited(tripleRefreshType(type));
  }

  void tripleSyncWithAreaState() {
    if (!_enabled) {
      debugPrint('🔕 [Triple] disabled → syncWithAreaState ignored');
      return;
    }

    debugPrint(
        '🔄 [Triple] syncWithAreaState (NO-SUBSCRIBE) → refresh active types');

    _baseline.clear();
    _clearPendingSelectionInternal();

    for (final t in _activeTypes.toList()) {
      unawaited(tripleRefreshType(t));
    }
  }

  void _initDefaultLoads() {
    tripleSubscribeType(PlateType.parkingCompleted);
    tripleSubscribeType(PlateType.departureCompleted);
  }

  Future<void> tripleRefreshType(PlateType type) async {
    if (!_enabled) return;
    if (!tripleAllowedTypes.contains(type)) return;

    final area = currentArea.trim();
    if (area.isEmpty) return;

    final int lifeToken = _lifecycleEpoch;
    final int seq = (_reqSeqByType[type] ?? 0) + 1;
    _reqSeqByType[type] = seq;

    final descending = _isSortedMap[type] ?? true;

    _loadingTypes.add(type);
    notifyListeners();

    debugPrint(
        '🔎 [Triple][${_getTypeLabel(type)}] 1회 로드 시작 (area=$area, desc=$descending)');

    try {
      final fetched = await _repository.fetchPlatesByTypeAndArea(
        type: type,
        area: area,
        descending: descending,
        cacheFirst: true,
      );

      final results = fetched.items;

      if (!_enabled) return;
      if (_lifecycleEpoch != lifeToken) return;
      if ((_reqSeqByType[type] ?? 0) != seq) return;

      _lastTripleRefreshAtByType[type] = DateTime.now();
      _lastTripleRefreshSourceByType[type] = fetched.sourceLabel;

      final prevIds = _lastIdsByType[type] ?? <String>{};
      final newIds = results.map((e) => e.id).toSet();
      final removedIds = prevIds.difference(newIds);
      _lastIdsByType[type] = newIds;

      if (type == PlateType.departureCompleted && removedIds.isNotEmpty) {
        for (final removedId in removedIds) {
          try {
            final fresh = await _repository.getPlate(removedId);
            if (fresh == null) continue;

            final sameArea = fresh.area == area;
            final isDepartureCompleted =
                fresh.type == PlateType.departureCompleted.firestoreValue;
            final isLockedFeeTrue = fresh.isLockedFee == true;

            if (sameArea && isDepartureCompleted && isLockedFeeTrue) {
              previousIsLockedFee[removedId] = true;
              debugPrint(
                  '✅ [Triple] 정산 전이 감지(1회 조회 비교): id=$removedId, plate=${fresh.plateNumber}');
            }
          } catch (e) {
            debugPrint('⚠️ [Triple] removed 후속 확인 실패: $e');
          }
        }
      }

      for (final p in results) {
        final tripleizedSelectedBy = p.isSelected
            ? ((p.selectedBy?.trim().isNotEmpty ?? false)
                ? p.selectedBy!.trim()
                : null)
            : null;

        _baseline[p.id] = _TripleSelectionBaseline(
          isSelected: p.isSelected,
          selectedBy: tripleizedSelectedBy,
        );
      }

      _data[type] = results;
      notifyListeners();

      if (hasPendingSelection && !pendingStillValidFor(type)) {
        _clearPendingSelectionInternal();
        notifyListeners();
        debugPrint('ℹ️ [Triple] 외부 변경/갱신으로 보류 선택을 해제했습니다.');
      }

      debugPrint(
          '✅ [Triple][${_getTypeLabel(type)}] 1회 로드 완료: ${results.length}개');
    } catch (e) {
      debugPrint('🔥 [Triple][${_getTypeLabel(type)}] 1회 로드 실패: $e');
    } finally {
      if (_enabled &&
          _lifecycleEpoch == lifeToken &&
          (_reqSeqByType[type] ?? 0) == seq) {
        _loadingTypes.remove(type);
        notifyListeners();
      }
    }
  }

  PlateModel? tripleGetSelectedPlate(PlateType collection, String userName) {
    final plates = _data[collection];
    if (plates == null || plates.isEmpty) return null;

    try {
      return plates.firstWhere(
          (plate) => plate.isSelected && plate.selectedBy == userName);
    } catch (_) {
      return null;
    }
  }

  Future<void> tripleTogglePlateIsSelected({
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
                    p.isSelected && p.selectedBy == userName && p.id != plateId,
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
                  statusList: const [],
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
        _clearPendingSelectionInternal();
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
          equalsBaseline =
              (base.isSelected == newIsSelected) && (baseSelBy == newSelBy);
        }
      }

      if (equalsBaseline) {
        if (_pendingPlateId == plateId) {
          _clearPendingSelectionInternal();
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

  List<PlateModel> tripleGetPlatesByCollection(PlateType collection,
      {DateTime? selectedDate}) {
    var plates = _data[collection] ?? <PlateModel>[];

    if (collection == PlateType.departureCompleted && selectedDate != null) {
      final start =
          DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      final end = start.add(const Duration(days: 1));

      plates = plates.where((p) {
        final t = p.endTime ?? p.updatedAt ?? p.requestTime;
        return !t.isBefore(start) && t.isBefore(end);
      }).toList();
    }

    return plates;
  }

  Future<void> tripleUpdatePlateLocally(
      PlateType collection, PlateModel updatedPlate) async {
    final list = _data[collection];
    if (list == null) return;

    final index = list.indexWhere((p) => p.id == updatedPlate.id);
    if (index != -1) {
      _data[collection]![index] = updatedPlate;
      notifyListeners();
    }
  }

  void _onAreaChanged() {
    if (!_enabled) return;

    debugPrint(
        '🔄 [Triple] area changed → refresh active types (NO-SUBSCRIBE)');

    _baseline.clear();
    _clearPendingSelectionInternal();

    for (final t in _activeTypes.toList()) {
      unawaited(tripleRefreshType(t));
    }
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
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
