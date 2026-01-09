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

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;
  final AreaState _areaState;

  // ✅ 필드 페이지에서만 스트림을 켜기 위한 스위치 (HQ에서는 false 유지)
  bool _enabled = false;

  /// ✅ BackEndController 등에서 “현재 PlateState 엔진이 켜져있는지” 확인용
  bool get isEnabled => _enabled;

  final Map<String, bool> previousIsLockedFee = {};

  final Map<PlateType, List<PlateModel>> _data = {
    for (var c in PlateType.values) c: [],
  };

  final Map<PlateType, StreamSubscription> _subscriptions = {};

  /// ✅ 실제 실행 중(= listen 보유) 구독인지 여부
  bool isActivelySubscribed(PlateType type) => _subscriptions.containsKey(type);

  /// ✅ 실제 활성 구독 개수
  int get activeSubscriptionCount => _subscriptions.length;

  final Map<PlateType, bool> _isSortedMap = {
    for (var c in PlateType.values) c: true,
  };

  final Map<PlateType, String> _subscribedAreas = {};

  bool _isLoading = false;

  /// ✅ “원하는 구독(스위치 의도)” 상태
  final Set<PlateType> _desiredSubscriptions = {};

  int get desiredSubscriptionCount => _desiredSubscriptions.length;

  // ─────────────────────────────────────────────────────────────
  // departureRequests에서 "사라진" 항목 감지를 위한 캐시 & 이벤트
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

  PlateState(this._repository, this._areaState) {
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
  /// withDefaults=true면 기본 3종(입차요청/출차요청/출차완료)을 즉시 구독합니다.
  /// 태블릿에서 “출차 요청만” 구독하려면 withDefaults=false로 켭니다.
  void enableForTypePages({bool withDefaults = true}) {
    if (_enabled) return;
    _enabled = true;
    debugPrint('🔔 PlateState enabled (Type pages) / withDefaults=$withDefaults');
    if (withDefaults) {
      _initDefaultSubscriptions();
    }
  }

  /// ✅ 완결 패치 핵심:
  /// - disableAll() 시 실제 구독(_subscriptions)만 끊으면 UI(희망 구독)와 상태가 어긋날 수 있음
  /// - 따라서 _desiredSubscriptions까지 함께 정리하여 “전환 직후 스위치도 OFF”가 되도록 보장
  void disableAll() {
    if (!_enabled && _subscriptions.isEmpty && _desiredSubscriptions.isEmpty) return;

    _enabled = false;
    debugPrint('🔕 PlateState disabled (HQ or leaving type pages)');

    // ✅ “희망 구독”까지 정리 → BackEndController 스위치 혼선 제거
    _desiredSubscriptions.clear();

    // 선택 보류/베이스라인/전이 캐시 정리
    _clearPendingSelection();
    _baseline.clear();
    previousIsLockedFee.clear();

    // 데이터/캐시 정리(잔상 방지)
    for (final t in PlateType.values) {
      _data[t] = [];
      _lastByType[t] = {};
    }

    _cancelAllSubscriptions();
  }

  // ─────────────────────────────────────────────────────────────
  // 📱 태블릿 전용 헬퍼들
  // ─────────────────────────────────────────────────────────────

  /// 📱 태블릿 전용: 기본 구독 없이 enable만 수행
  void tabletEnableWithoutDefaults() {
    debugPrint('📱 [Tablet] tabletEnableWithoutDefaults() → area=$currentArea');
    enableForTypePages(withDefaults: false);
  }

  /// 📱 태블릿 전용: 출차 요청만 구독 (기본 구독 없이 보장)
  void tabletSubscribeDeparture() {
    debugPrint('📱 [Tablet] tabletSubscribeDeparture() → before: enabled=$_enabled, area=$currentArea, '
        'desired=${_desiredSubscriptions.map((e) => e.name).toList()}');
    enableForTypePages(withDefaults: false);
    if (!isSubscribed(PlateType.departureRequests)) {
      subscribeType(PlateType.departureRequests);
      debugPrint('📱 [Tablet] ▶ subscribeType(departureRequests) started for area=$currentArea');
    } else {
      // 이미 구독 중이더라도 지역이 달라진 경우 subscribeType 내부에서 재구독 처리
      subscribeType(PlateType.departureRequests);
      debugPrint('📱 [Tablet] ℹ️ departureRequests already desired → ensured (area=$currentArea)');
    }
  }

  /// 📱 태블릿 전용: 출차 요청 구독 해제
  void tabletUnsubscribeDeparture() {
    debugPrint('📱 [Tablet] tabletUnsubscribeDeparture() → before: enabled=$_enabled, area=$currentArea, '
        'desired=${_desiredSubscriptions.map((e) => e.name).toList()}');
    if (isSubscribed(PlateType.departureRequests)) {
      unsubscribeType(PlateType.departureRequests);
      debugPrint('📱 [Tablet] ⏹ unsubscribeType(departureRequests) for area=$currentArea');
    } else {
      debugPrint('📱 [Tablet] ⚠️ departureRequests not subscribed (no-op)');
    }
  }

  // ─────────────────────────────────────────────────────────────

  void subscribeType(PlateType type) {
    // ✅ HQ 등 비활성 상태면 아무 것도 하지 않음 (비용 방지)
    if (!_enabled) {
      debugPrint('🔕 PlateState disabled → subscribeType 무시: $type');
      return;
    }

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

        // 서버 베이스라인 갱신 (해제 상태면 selectedBy를 null로 정규화)
        for (final p in results) {
          final normalizedSelectedBy =
              p.isSelected ? ((p.selectedBy?.trim().isNotEmpty ?? false) ? p.selectedBy!.trim() : null) : null;
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
              debugPrint('✅ 정산 전이 감지: doc=${fresh.id}, plate=${data['plateNumber']}');

              final key = (data['id'] ?? fresh.id).toString();
              previousIsLockedFee[key] = true;
            }
          } catch (e) {
            debugPrint('⚠️ [출차 완료 전이 감지] removed 처리 실패: $e');
          }
        }

        // ⬇️ 스트림 갱신 이후 보류 유효성 재점검
        if (hasPendingSelection && !pendingStillValidFor(type)) {
          _clearPendingSelection();
          notifyListeners();
          debugPrint('ℹ️ 전환/필터/외부 변경으로 보류를 해제했습니다.');
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
      // departureRequests만 "사라진 문서" 감지
      if (type == PlateType.departureRequests) {
        final lastMap = _lastByType[type] ?? {};
        final currentMap = {for (final p in filteredData) p.id: p};

        // last - current = 사라진 문서들
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
        final normalizedSelectedBy =
            p.isSelected ? ((p.selectedBy?.trim().isNotEmpty ?? false) ? p.selectedBy!.trim() : null) : null;
        _baseline[p.id] = _SelectionBaseline(
          isSelected: p.isSelected,
          selectedBy: normalizedSelectedBy,
        );
      }

      _data[type] = filteredData;
      notifyListeners();

      // ⬇️ 스트림 갱신 이후 보류 유효성 재점검
      if (hasPendingSelection && !pendingStillValidFor(type)) {
        _clearPendingSelection();
        notifyListeners();
        debugPrint('ℹ️ 전환/필터/외부 변경으로 보류를 해제했습니다.');
      }

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

  /// ✅ 완결 패치(보강):
  /// - 구독 중이 아니더라도, “해제”는 항상 UI/캐시 상태를 정리하도록 보장
  void unsubscribeType(PlateType type) {
    _desiredSubscriptions.remove(type);

    final sub = _subscriptions[type];
    final area = _subscribedAreas[type];

    if (sub != null) {
      sub.cancel();
    }

    _subscriptions.remove(type);
    _subscribedAreas.remove(type);

    _data[type] = [];
    _lastByType[type] = {};

    notifyListeners();

    if (area != null) {
      debugPrint('🛑 [${_getTypeLabel(type)}] 구독 해제됨 (지역: $area)');
    } else {
      debugPrint('🛑 [${_getTypeLabel(type)}] 구독 해제됨');
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

      // 동시 선택 제어(로컬 기준)
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

      // ── (옵션) 다른 plate에 보류가 잡혀 있으면 롤백하여 한 번에 하나만 보류
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

      // ── 로컬 토글
      final newIsSelected = !plate.isSelected;
      final newSelectedBy = newIsSelected ? userName : null;

      _data[collection]![index] = plate.copyWith(
        isSelected: newIsSelected,
        selectedBy: newSelectedBy,
      );

      // ✅ 베이스라인과 동일 여부 체크(해제는 selectedBy 무시, 선택은 trim 비교)
      final base = _baseline[plateId];
      bool equalsBaseline = false;
      if (base != null) {
        if (!newIsSelected && base.isSelected == false) {
          // 해제 상태는 selectedBy 의미 없음
          equalsBaseline = true;
        } else {
          final baseSelBy = (base.selectedBy ?? '').trim();
          final newSelBy = (newSelectedBy ?? '').trim();
          equalsBaseline = (base.isSelected == newIsSelected) && (baseSelBy == newSelBy);
        }
      }

      if (equalsBaseline) {
        // 원상복구된 상태 → 보류 해제
        if (_pendingPlateId == plateId) {
          _clearPendingSelection();
        }
      } else {
        // 서버와 상태가 다르면 보류 설정
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

  /// ✅ 보류 유효성 검사(해제는 selectedBy 무시, 선택은 trim 비교)
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

    // 2) 서버 베이스라인이 이미 보류 상태와 동일 → 커밋 불필요
    if (base != null) {
      if (!pendSel && base.isSelected == false) {
        // 해제는 selectedBy 무시
        return false;
      } else if (pendSel && base.isSelected == true) {
        final baseSelBy = (base.selectedBy ?? '').trim();
        final pendByNorm = (pendBy ?? '').trim();
        if (baseSelBy == pendByNorm) {
          return false;
        }
      }
    }

    // 3) 외부 편집 등으로 해제된 상태(서버/로컬 모두 false/null)에서 보류가 '선택(true)'을 요구하면 무효
    if (pendSel &&
        p.isSelected == false &&
        p.selectedBy == null &&
        base != null &&
        base.isSelected == false &&
        base.selectedBy == null) {
      return false;
    }

    // 그 외에는 커밋 의미 있음
    return true;
  }

  /// ✅ (신규) 보류된 선택/해제를 실제 Firestore에 반영
  Future<void> commitPendingSelection({
    required void Function(String) onError,
  }) async {
    if (!hasPendingSelection) return;

    final plateId = _pendingPlateId!;
    final isSelected = _pendingIsSelected!;
    final selectedBy = _pendingSelectedBy;
    final expected = _pendingCollection!;

    // 1) 서버 스냅샷 기준으로 보류 유효성 검사(헛커밋 차단)
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

      // 커밋 성공 → 서버 베이스라인을 새 상태로 갱신(해제 시 selectedBy는 null로)
      _baseline[plateId] = _SelectionBaseline(
        isSelected: isSelected,
        selectedBy: isSelected ? ((selectedBy?.trim().isNotEmpty ?? false) ? selectedBy!.trim() : null) : null,
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
      debugPrint("🔕 PlateState disabled → syncWithAreaState 무시");
      return;
    }

    // 🚧 중복 방지 가드:
    final desired = _desiredSubscriptions.toSet();
    final subscribedTypes = _subscriptions.keys.toSet();
    final sameTypes = desired.length == subscribedTypes.length && desired.containsAll(subscribedTypes);
    final sameAreaAll = _subscribedAreas.values.every((a) => a == currentArea);
    if (sameTypes && sameAreaAll) {
      debugPrint("ℹ️ syncWithAreaState: 동일 구성/지역 → 재구독 생략");
      return;
    }

    debugPrint("🔄 syncWithAreaState : 지역 변경 감지 및 상태 갱신 호출됨");
    _cancelAllSubscriptions();
    _clearPendingSelection(); // 지역 변경 시 보류 상태도 초기화
    _baseline.clear(); // 베이스라인 초기화
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
    if (!_enabled) {
      debugPrint("🔕 PlateState disabled → _onAreaChanged 무시");
      return;
    }
    debugPrint("🔄 지역 변경 감지됨: ${_areaState.currentArea}");
    _cancelAllSubscriptions();
    _clearPendingSelection(); // 지역 변경 시 보류 상태도 초기화
    _baseline.clear(); // 베이스라인 초기화
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
