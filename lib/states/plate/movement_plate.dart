import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_write_service.dart';
import '../user/user_state.dart';

/// ✅ (리팩터링) View Sync Gate
/// - Write 토글(기본) + Tab 토글(보조)을 OR로 묶어 "정합성" 기준으로 동작
/// - PlateWriteService.updatePlate()의 shouldSync*() 정책과 같은 철학
class _ViewSyncGate {
  final String name;
  final String writePrefsKey;
  final String? tabPrefsKey;

  const _ViewSyncGate({
    required this.name,
    required this.writePrefsKey,
    this.tabPrefsKey,
  });

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<SharedPreferences> _ensurePrefs() async {
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
    return _prefs!;
  }

  Future<bool> _getBool(String key) async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(key) ?? false; // 기본 OFF
  }

  /// ✅ 정합성 기준: write ON이면 true, 아니면 tab ON이면 true
  Future<bool> shouldSync() async {
    final writeOn = await _getBool(writePrefsKey);
    if (writeOn) return true;
    if (tabPrefsKey == null) return false;
    return _getBool(tabPrefsKey!);
  }

  Future<String> debugReason() async {
    final writeOn = await _getBool(writePrefsKey);
    final tabOn = tabPrefsKey == null ? false : await _getBool(tabPrefsKey!);
    return 'write=${writeOn ? "ON" : "OFF"}, tab=${tabOn ? "ON" : "OFF"}';
  }
}

class MovementPlate extends ChangeNotifier {
  final PlateWriteService _write;
  final UserState _user;

  MovementPlate(this._write, this._user);

  /// ✅ (기존) 경량 View 컬렉션명
  static const String _parkingCompletedViewCollection = 'parking_completed_view';

  /// ✅ (기존) 출차 요청 View 컬렉션명
  static const String _departureRequestsViewCollection = 'departure_requests_view';

  /// ✅ (기존/신규) 입차 요청 View 컬렉션명
  static const String _parkingRequestsViewCollection = 'parking_requests_view';

  // ─────────────────────────────────────────
  // ✅ Gate 키 (UI 토글과 반드시 동일해야 함)
  // ─────────────────────────────────────────

  static const String _kPcWrite = 'parking_completed_realtime_write_enabled_v1';
  static const String _kDepWrite = 'departure_requests_realtime_write_enabled_v1';
  static const String _kReqWrite = 'parking_requests_realtime_write_enabled_v1';

  static const String _kPcTab = 'parking_completed_realtime_tab_enabled_v1';
  static const String _kDepTab = 'departure_requests_realtime_tab_enabled_v1';

  // ⚠️ UI에 해당 키가 없다면 항상 OFF로 평가됨.
  // - 만약 UI에 입차요청 테이블 탭 토글이 존재한다면 동일 키로 맞추세요.
  static const String _kReqTab = 'parking_requests_realtime_tab_enabled_v1';

  final _ViewSyncGate _pcGate = const _ViewSyncGate(
    name: 'parking_completed_view',
    writePrefsKey: _kPcWrite,
    tabPrefsKey: _kPcTab,
  );

  final _ViewSyncGate _depGate = const _ViewSyncGate(
    name: 'departure_requests_view',
    writePrefsKey: _kDepWrite,
    tabPrefsKey: _kDepTab,
  );

  final _ViewSyncGate _reqGate = const _ViewSyncGate(
    name: 'parking_requests_view',
    writePrefsKey: _kReqWrite,
    tabPrefsKey: _kReqTab,
  );

  /// ✅ plates 문서명과 동일한 docId를 항상 만들기 위한 헬퍼
  String _plateDocId(String plateNumber, String area) => '${plateNumber}_$area';

  /// ✅ view 문서는 area 1개(=..._view/{area})
  DocumentReference<Map<String, dynamic>> _pcViewRef(String area) =>
      FirebaseFirestore.instance.collection(_parkingCompletedViewCollection).doc(area);

  DocumentReference<Map<String, dynamic>> _depViewRef(String area) =>
      FirebaseFirestore.instance.collection(_departureRequestsViewCollection).doc(area);

  DocumentReference<Map<String, dynamic>> _reqViewRef(String area) =>
      FirebaseFirestore.instance.collection(_parkingRequestsViewCollection).doc(area);

  void _debugOps({
    required String action,
    required String plateNumber,
    required String area,
    required String plateDocId,
    required int txReads,
    required int txWrites,
    required int viewWritesMin,
    required int viewWritesMax,
    String? gateReason,
  }) {
    // Firestore 과금 형태(문서 단위): READ / WRITE / DELETE
    // - transaction은 내부적으로 READ 1 + WRITE 1 형태(plate doc)
    // - view sync는 doc(area) 1개에 대해 set(merge) => WRITE 1
    debugPrint(
      '🧾 [MovementPlate] $action plate=$plateNumber area=$area id=$plateDocId '
          '| 예상 ops: TX_READ=$txReads, TX_WRITE=$txWrites, VIEW_WRITES=$viewWritesMin..$viewWritesMax'
          '${gateReason != null ? " | gate($gateReason)" : ""}',
    );
  }

  // ─────────────────────────────────────────
  // parking_completed_view upsert/remove
  // ─────────────────────────────────────────

  Future<void> _upsertParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    final should = await _pcGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_completed_view upsert (${await _pcGate.debugReason()})');
      }
      return;
    }

    try {
      final ref = _pcViewRef(area);
      await ref.set(
        <String, dynamic>{
          'area': area,
          'updatedAt': FieldValue.serverTimestamp(),
          'items': <String, dynamic>{
            plateDocId: <String, dynamic>{
              'plateNumber': plateNumber,
              'location': location.isNotEmpty ? location : '미지정',
              'parkingCompletedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ parking_completed_view upsert 실패: $e');
    }
  }

  Future<void> _removeParkingCompletedViewItem({
    required String area,
    required String plateDocId,
  }) async {
    final should = await _pcGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_completed_view remove (${await _pcGate.debugReason()})');
      }
      return;
    }

    try {
      final ref = _pcViewRef(area);
      await ref.set(
        <String, dynamic>{
          'area': area,
          'updatedAt': FieldValue.serverTimestamp(),
          'items': <String, dynamic>{
            plateDocId: FieldValue.delete(),
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ parking_completed_view remove 실패: $e');
    }
  }

  // ─────────────────────────────────────────
  // departure_requests_view upsert/remove
  // ─────────────────────────────────────────

  Future<void> _upsertDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    final should = await _depGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip departure_requests_view upsert (${await _depGate.debugReason()})');
      }
      return;
    }

    try {
      final ref = _depViewRef(area);
      await ref.set(
        <String, dynamic>{
          'area': area,
          'updatedAt': FieldValue.serverTimestamp(),
          'items': <String, dynamic>{
            plateDocId: <String, dynamic>{
              'plateNumber': plateNumber,
              'location': location.isNotEmpty ? location : '미지정',
              'departureRequestedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ departure_requests_view upsert 실패: $e');
    }
  }

  Future<void> _removeDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
  }) async {
    final should = await _depGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip departure_requests_view remove (${await _depGate.debugReason()})');
      }
      return;
    }

    try {
      final ref = _depViewRef(area);
      await ref.set(
        <String, dynamic>{
          'area': area,
          'updatedAt': FieldValue.serverTimestamp(),
          'items': <String, dynamic>{
            plateDocId: FieldValue.delete(),
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ departure_requests_view remove 실패: $e');
    }
  }

  // ─────────────────────────────────────────
  // parking_requests_view upsert/remove
  // ─────────────────────────────────────────

  Future<void> _upsertParkingRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    final should = await _reqGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_requests_view upsert (${await _reqGate.debugReason()})');
      }
      return;
    }

    try {
      final ref = _reqViewRef(area);
      await ref.set(
        <String, dynamic>{
          'area': area,
          'updatedAt': FieldValue.serverTimestamp(),
          'items': <String, dynamic>{
            plateDocId: <String, dynamic>{
              'plateNumber': plateNumber,
              'location': location.isNotEmpty ? location : '미지정',
              'parkingRequestedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ parking_requests_view upsert 실패: $e');
    }
  }

  Future<void> _removeParkingRequestsViewItem({
    required String area,
    required String plateDocId,
  }) async {
    final should = await _reqGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_requests_view remove (${await _reqGate.debugReason()})');
      }
      return;
    }

    try {
      final ref = _reqViewRef(area);
      await ref.set(
        <String, dynamic>{
          'area': area,
          'updatedAt': FieldValue.serverTimestamp(),
          'items': <String, dynamic>{
            plateDocId: FieldValue.delete(),
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ parking_requests_view remove 실패: $e');
    }
  }

  // ─────────────────────────────────────────
  // 상태 전이 API들
  // ─────────────────────────────────────────

  /// 입차 완료 (parking_requests → parking_completed)
  Future<void> setParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

    // 예상 비용 형태:
    // - TX: plates doc READ 1 + WRITE 1
    // - VIEW: req remove(0..1) + pc upsert(0..1)
    _debugOps(
      action: 'setParkingCompleted(requests→completed)',
      plateNumber: plateNumber,
      area: area,
      plateDocId: plateDocId,
      txReads: 1,
      txWrites: 1,
      viewWritesMin: 0,
      viewWritesMax: 2,
      gateReason: 'pc(${await _pcGate.debugReason()}), req(${await _reqGate.debugReason()})',
    );

    await _write.transitionPlateType(
      plateId: plateDocId,
      actor: actor,
      fromType: PlateType.parkingRequests.firestoreValue,
      toType: PlateType.parkingCompleted.firestoreValue,
      extraFields: {
        'location': location,
        'area': area,
        'parkingCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    await _removeParkingRequestsViewItem(area: area, plateDocId: plateDocId);
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );
  }

  /// 출차 요청 (parking_completed → departure_requests)
  Future<void> setDepartureRequested(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

    _debugOps(
      action: 'setDepartureRequested(completed→departure_requests)',
      plateNumber: plateNumber,
      area: area,
      plateDocId: plateDocId,
      txReads: 1,
      txWrites: 1,
      viewWritesMin: 0,
      viewWritesMax: 2,
      gateReason: 'pc(${await _pcGate.debugReason()}), dep(${await _depGate.debugReason()})',
    );

    await _write.transitionPlateType(
      plateId: plateDocId,
      actor: actor,
      fromType: PlateType.parkingCompleted.firestoreValue,
      toType: PlateType.departureRequests.firestoreValue,
      extraFields: {
        'location': location,
        'area': area,
        'departureRequestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    await _removeParkingCompletedViewItem(area: area, plateDocId: plateDocId);
    await _upsertDepartureRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );
  }

  /// 출차 완료 "직접" 처리 (parking_completed → departure_completed)
  Future<void> setDepartureCompletedDirectFromParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

    _debugOps(
      action: 'setDepartureCompletedDirectFromParkingCompleted(completed→departure_completed)',
      plateNumber: plateNumber,
      area: area,
      plateDocId: plateDocId,
      txReads: 1,
      txWrites: 1,
      viewWritesMin: 0,
      viewWritesMax: 1, // pc remove only
      gateReason: 'pc(${await _pcGate.debugReason()})',
    );

    await _write.transitionPlateType(
      plateId: plateDocId,
      actor: actor,
      fromType: PlateType.parkingCompleted.firestoreValue,
      toType: PlateType.departureCompleted.firestoreValue,
      extraFields: {
        'area': area,
        'location': location,
        'departureCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    await _removeParkingCompletedViewItem(area: area, plateDocId: plateDocId);
  }

  /// 출차 완료 (departure_requests → departure_completed)
  Future<void> setDepartureCompleted(
      PlateModel selectedPlate, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;

    final plateDocId = (selectedPlate.id.isNotEmpty)
        ? selectedPlate.id
        : _plateDocId(selectedPlate.plateNumber, selectedPlate.area);

    _debugOps(
      action: 'setDepartureCompleted(departure_requests→departure_completed)',
      plateNumber: selectedPlate.plateNumber,
      area: selectedPlate.area,
      plateDocId: plateDocId,
      txReads: 1,
      txWrites: 1,
      viewWritesMin: 0,
      viewWritesMax: 1, // dep remove only
      gateReason: 'dep(${await _depGate.debugReason()})',
    );

    await _write.transitionPlateType(
      plateId: plateDocId,
      actor: actor,
      fromType: PlateType.departureRequests.firestoreValue,
      toType: PlateType.departureCompleted.firestoreValue,
      extraFields: {
        'area': selectedPlate.area,
        'location': selectedPlate.location,
        'departureCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    await _removeDepartureRequestsViewItem(area: selectedPlate.area, plateDocId: plateDocId);
  }

  /// (옵션) 출차 요청 → 입차 완료 되돌리기
  Future<void> goBackToParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

    _debugOps(
      action: 'goBackToParkingCompleted(departure_requests→completed)',
      plateNumber: plateNumber,
      area: area,
      plateDocId: plateDocId,
      txReads: 1,
      txWrites: 1,
      viewWritesMin: 0,
      viewWritesMax: 2, // dep remove + pc upsert
      gateReason: 'dep(${await _depGate.debugReason()}), pc(${await _pcGate.debugReason()})',
    );

    await _write.transitionPlateType(
      plateId: plateDocId,
      actor: actor,
      fromType: PlateType.departureRequests.firestoreValue,
      toType: PlateType.parkingCompleted.firestoreValue,
      extraFields: {
        'area': area,
        'location': location,
        'parkingCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    await _removeDepartureRequestsViewItem(area: area, plateDocId: plateDocId);
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );
  }

  /// (옵션) 임의 상태 → 입차 요청 되돌리기
  /// ✅ "입차 요청으로 되돌리면 parking_requests_view에 생성",
  ///    "기존 view(출차요청/입차완료)에서는 제거"
  Future<void> goBackToParkingRequest({
    required PlateType fromType,
    required String plateNumber,
    required String area,
    required String newLocation,
    bool forceOverride = true,
  }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

    _debugOps(
      action: 'goBackToParkingRequest(${fromType.firestoreValue}→parking_requests)',
      plateNumber: plateNumber,
      area: area,
      plateDocId: plateDocId,
      txReads: 1,
      txWrites: 1,
      viewWritesMin: 0,
      viewWritesMax: 2, // remove(0..1) + req upsert(0..1)
      gateReason: 'req(${await _reqGate.debugReason()}), pc/dep gates apply if removing',
    );

    await _write.transitionPlateType(
      plateId: plateDocId,
      actor: actor,
      fromType: fromType.firestoreValue,
      toType: PlateType.parkingRequests.firestoreValue,
      extraFields: {
        'area': area,
        'location': newLocation,
        'requestTime': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    // ✅ 기존 view 정리
    if (fromType == PlateType.parkingCompleted) {
      await _removeParkingCompletedViewItem(area: area, plateDocId: plateDocId);
    } else if (fromType == PlateType.departureRequests) {
      await _removeDepartureRequestsViewItem(area: area, plateDocId: plateDocId);
    }

    await _upsertParkingRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: newLocation,
    );
  }
}
