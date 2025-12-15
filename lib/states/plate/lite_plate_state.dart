import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_repository.dart';
import '../area/area_state.dart';

/// 서버 스냅샷 기준의 선택 상태를 plateId별로 보관하기 위한 베이스라인
class _SelectionBaseline {
  final bool isSelected;
  final String? selectedBy;

  const _SelectionBaseline({required this.isSelected, required this.selectedBy});
}

class LitePlateState extends ChangeNotifier {
  /// ✅ Lite 모드에서는 "입차 완료/출차 완료"만 사용(데이터 대상 제한)
  static const Set<PlateType> liteAllowedTypes = {
    PlateType.parkingCompleted,
    PlateType.departureCompleted,
  };

  final PlateRepository _repository;
  final AreaState _areaState;

  /// ✅ Lite 모드에서 “구독”을 절대 하지 않기 위해:
  /// - StreamSubscription, snapshots().listen() 사용 금지
  /// - 읽기는 FirebaseFirestore.get() 기반 1회 조회로만 처리
  bool _enabled = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 로딩 상태: 여러 타입 동시 로드 가능하므로 Set으로 관리
  final Set<PlateType> _loadingTypes = <PlateType>{};
  bool get isLoading => _loadingTypes.isNotEmpty;

  /// Lite에서도 기존 로직 호환을 위해 유지
  final Map<String, bool> previousIsLockedFee = <String, bool>{};

  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: <PlateModel>[],
  };

  List<PlateModel> dataOfType(PlateType type) => _data[type] ?? <PlateModel>[];

  /// 정렬 방향 저장
  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  /// “활성화된 타입(= 화면에서 사용 중인 타입)” 기록
  final Set<PlateType> _activeTypes = <PlateType>{};

  /// 마지막 조회 결과 ID 셋 (removed 감지용)
  final Map<PlateType, Set<String>> _lastIdsByType = {
    for (var c in PlateType.values) c: <String>{},
  };

  /// plateId별 서버 기준 선택 상태 베이스라인
  final Map<String, _SelectionBaseline> _baseline = <String, _SelectionBaseline>{};

  /// ✅ 선택/해제 지연 반영을 위한 보류 상태
  PlateType? _pendingCollection;
  String? _pendingPlateId;
  bool? _pendingIsSelected;
  String? _pendingSelectedBy;

  bool get hasPendingSelection =>
      _pendingCollection != null && _pendingPlateId != null && _pendingIsSelected != null;

  bool? get pendingIsSelected => _pendingIsSelected;

  /// 라이프사이클 변경(비활성/지역 변경) 토큰
  int _lifecycleEpoch = 0;

  /// 타입별 최신 요청 시퀀스(동시 로드 시 서로 결과 폐기하지 않도록)
  final Map<PlateType, int> _reqSeqByType = {
    for (var c in PlateType.values) c: 0,
  };

  LitePlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged);
  }

  String get currentArea => _areaState.currentArea;

  void _clearPendingSelectionInternal() {
    _pendingCollection = null;
    _pendingPlateId = null;
    _pendingIsSelected = null;
    _pendingSelectedBy = null;
  }

  /// 🔸 외부 동작으로 동일 plateId의 선택 의도가 무의미해졌을 때 호출
  void clearPendingSelection() {
    _clearPendingSelectionInternal();
    notifyListeners();
  }

  /// 🔸 특정 plateId와 일치할 때만 보류 선택을 해제
  void clearPendingIfMatches(String plateId) {
    if (_pendingPlateId == plateId) {
      _clearPendingSelectionInternal();
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 공개 스위치: Lite 화면에서만 데이터 로드 활성화
  // ─────────────────────────────────────────────────────────────

  /// Lite 모드: withDefaults=true면 "입차완료/출차완료" 2종을 1회 조회로 로드합니다.
  /// (중요) 여기서 “구독”은 절대 하지 않습니다.
  void enableForTypePages({bool withDefaults = true}) {
    if (_enabled) return;
    _enabled = true;

    debugPrint('🔔 [Lite] LitePlateState enabled (NO-SUBSCRIBE) / withDefaults=$withDefaults');

    if (withDefaults) {
      _initDefaultLoads();
    }
  }

  void disableAll() {
    if (!_enabled && _activeTypes.isEmpty) return;

    _enabled = false;
    _lifecycleEpoch++; // 진행 중 로드 결과 무시
    debugPrint('🔕 [Lite] LitePlateState disabled (NO-SUBSCRIBE)');

    _activeTypes.clear();
    _baseline.clear();
    _clearPendingSelectionInternal();

    for (final t in PlateType.values) {
      _data[t] = <PlateModel>[];
      _lastIdsByType[t] = <String>{};
      _reqSeqByType[t] = 0;
    }

    _loadingTypes.clear();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // “subscribe/unsubscribe” API는 유지하되,
  // 의미를 “활성화 + 1회 로드”로 변경 (구독 금지)
  // ─────────────────────────────────────────────────────────────

  void subscribeType(PlateType type) {
    if (!liteAllowedTypes.contains(type)) {
      debugPrint('🚫 [Lite] subscribeType ignored (not allowed): $type');
      return;
    }
    if (!_enabled) {
      debugPrint('🔕 [Lite] disabled → subscribeType ignored: $type');
      return;
    }

    _activeTypes.add(type);

    // “구독 시작”이 아니라 “1회 로드”로 동작
    unawaited(refreshType(type));
  }

  void unsubscribeType(PlateType type) {
    if (!liteAllowedTypes.contains(type)) {
      debugPrint('🚫 [Lite] unsubscribeType ignored (not allowed): $type');
      return;
    }

    _activeTypes.remove(type);
    _data[type] = <PlateModel>[];
    _lastIdsByType[type] = <String>{};

    notifyListeners();
    debugPrint('🧹 [Lite][${_getTypeLabel(type)}] 데이터 비움 (NO-SUBSCRIBE)');
  }

  /// 정렬 변경 시: (구독이 없으므로) 즉시 1회 재조회로 반영
  void updateSortOrder(PlateType type, bool descending) {
    _isSortedMap[type] = descending;
    notifyListeners();

    if (_enabled && _activeTypes.contains(type) && liteAllowedTypes.contains(type)) {
      unawaited(refreshType(type));
    }
  }

  /// Area 변경 감지 시: 활성 타입들만 1회 재조회
  void syncWithAreaState() {
    if (!_enabled) {
      debugPrint('🔕 [Lite] disabled → syncWithAreaState ignored');
      return;
    }

    debugPrint('🔄 [Lite] syncWithAreaState (NO-SUBSCRIBE) → refresh active types');

    _baseline.clear();
    _clearPendingSelectionInternal();

    for (final t in _activeTypes.toList()) {
      unawaited(refreshType(t));
    }
  }

  void _initDefaultLoads() {
    // Lite 기본: 입차 완료 + 출차 완료
    subscribeType(PlateType.parkingCompleted);
    subscribeType(PlateType.departureCompleted);
  }

  // ─────────────────────────────────────────────────────────────
  // 1회 조회 로직 (중요: snapshots.listen 금지)
  // ─────────────────────────────────────────────────────────────

  Query<Map<String, dynamic>> _baseQuery({
    required PlateType type,
    required String area,
    required bool descending,
  }) {
    Query<Map<String, dynamic>> q = _firestore
        .collection('plates')
        .where(PlateFields.type, isEqualTo: type.firestoreValue)
        .where(PlateFields.area, isEqualTo: area);

    // departureCompleted는 “미정산(isLockedFee=false)”만 대상
    if (type == PlateType.departureCompleted) {
      q = q.where(PlateFields.isLockedFee, isEqualTo: false);
    }

    q = q.orderBy(PlateFields.requestTime, descending: descending);
    return q;
  }

  Future<List<PlateModel>> _getOnce({
    required PlateType type,
    required String area,
    required bool descending,
    bool cacheFirst = true,
  }) async {
    final query = _baseQuery(type: type, area: area, descending: descending);

    QuerySnapshot<Map<String, dynamic>> snap;

    if (cacheFirst) {
      try {
        snap = await query.get(const GetOptions(source: Source.cache));
      } catch (_) {
        snap = await query.get(const GetOptions(source: Source.server));
      }
    } else {
      snap = await query.get(const GetOptions(source: Source.server));
    }

    final results = <PlateModel>[];
    for (final doc in snap.docs) {
      try {
        results.add(PlateModel.fromDocument(doc));
      } catch (e) {
        debugPrint('❌ [Lite] parse error: type=$type, doc=${doc.id}, err=$e');
      }
    }
    return results;
  }

  Future<void> refreshType(PlateType type) async {
    if (!_enabled) return;
    if (!liteAllowedTypes.contains(type)) return;

    final area = currentArea.trim();
    if (area.isEmpty) return;

    final int lifeToken = _lifecycleEpoch;
    final int seq = (_reqSeqByType[type] ?? 0) + 1;
    _reqSeqByType[type] = seq;

    final descending = _isSortedMap[type] ?? true;

    _loadingTypes.add(type);
    notifyListeners();

    debugPrint('🔎 [Lite][${_getTypeLabel(type)}] 1회 로드 시작 (area=$area, desc=$descending)');

    try {
      // ✅ get 기반 1회 조회 (NO-SUBSCRIBE)
      final results = await _getOnce(
        type: type,
        area: area,
        descending: descending,
        cacheFirst: true,
      );

      // 중간에 disable/area 전환 등으로 토큰이 바뀌었으면 결과 폐기
      if (!_enabled) return;
      if (_lifecycleEpoch != lifeToken) return;
      if ((_reqSeqByType[type] ?? 0) != seq) return;

      // removed 감지: 이전/현재 ID 비교로 대체
      final prevIds = _lastIdsByType[type] ?? <String>{};
      final newIds = results.map((e) => e.id).toSet();
      final removedIds = prevIds.difference(newIds);
      _lastIdsByType[type] = newIds;

      // departureCompleted에서 removed된 항목은 isLockedFee=true로 전이되었는지 확인
      if (type == PlateType.departureCompleted && removedIds.isNotEmpty) {
        for (final removedId in removedIds) {
          try {
            final fresh = await _repository.getPlate(removedId);
            if (fresh == null) continue;

            final sameArea = fresh.area == area;
            final isDepartureCompleted = fresh.type == PlateType.departureCompleted.firestoreValue;
            final isLockedFeeTrue = fresh.isLockedFee == true;

            if (sameArea && isDepartureCompleted && isLockedFeeTrue) {
              previousIsLockedFee[removedId] = true;
              debugPrint('✅ [Lite] 정산 전이 감지(1회 조회 비교): id=$removedId, plate=${fresh.plateNumber}');
            }
          } catch (e) {
            debugPrint('⚠️ [Lite] removed 후속 확인 실패: $e');
          }
        }
      }

      // 서버 베이스라인 갱신
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

      // 보류 유효성 점검
      if (hasPendingSelection && !pendingStillValidFor(type)) {
        _clearPendingSelectionInternal();
        notifyListeners();
        debugPrint('ℹ️ [Lite] 외부 변경/갱신으로 보류 선택을 해제했습니다.');
      }

      debugPrint('✅ [Lite][${_getTypeLabel(type)}] 1회 로드 완료: ${results.length}개');
    } catch (e) {
      debugPrint('🔥 [Lite][${_getTypeLabel(type)}] 1회 로드 실패: $e');
    } finally {
      // 토큰이 살아있을 때만 로딩 해제
      if (_enabled && _lifecycleEpoch == lifeToken && (_reqSeqByType[type] ?? 0) == seq) {
        _loadingTypes.remove(type);
        notifyListeners();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 선택 로직 (기존 구조 유지)
  // ─────────────────────────────────────────────────────────────

  PlateModel? getSelectedPlate(PlateType collection, String userName) {
    final plates = _data[collection];
    if (plates == null || plates.isEmpty) return null;

    try {
      return plates.firstWhere((plate) => plate.isSelected && plate.selectedBy == userName);
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

      // 다른 plateId에 대한 보류가 있으면 베이스라인으로 복구
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
          equalsBaseline = (base.isSelected == newIsSelected) && (baseSelBy == newSelBy);
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

  Future<void> commitPendingSelection({
    required void Function(String) onError,
  }) async {
    if (!hasPendingSelection) return;

    final plateId = _pendingPlateId!;
    final isSelected = _pendingIsSelected!;
    final selectedBy = _pendingSelectedBy;
    final expected = _pendingCollection!;

    if (!pendingStillValidFor(expected)) {
      _clearPendingSelectionInternal();
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

      _clearPendingSelectionInternal();
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
    var plates = _data[collection] ?? <PlateModel>[];

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

  Future<void> updatePlateLocally(PlateType collection, PlateModel updatedPlate) async {
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

    debugPrint('🔄 [Lite] area changed → refresh active types (NO-SUBSCRIBE)');

    _baseline.clear();
    _clearPendingSelectionInternal();

    for (final t in _activeTypes.toList()) {
      unawaited(refreshType(t));
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
