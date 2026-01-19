import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_write_service.dart';
import '../../screens/service_mode/type_package/common_widgets/reverse_sheet_package/services/parking_completed_logger.dart';
import '../../screens/service_mode/type_package/common_widgets/reverse_sheet_package/services/status_mapping.dart';
import '../user/user_state.dart';

/// ✅ parking_completed_view "쓰기(Upsert/Delete)"를 기기 로컬 토글(SharedPreferences)로 제어
/// - UI 토글과 동일 키를 사용해야 실제로 연동됩니다.
class _ParkingCompletedViewWriteGate {
  static const String prefsKey = 'parking_completed_realtime_write_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
  }

  static Future<bool> canWrite() async {
    await _ensureLoaded();
    return _prefs!.getBool(prefsKey) ?? false; // 기본 OFF
  }
}

/// ✅ departure_requests_view "쓰기(Upsert/Delete)"를 기기 로컬 토글(SharedPreferences)로 제어
/// - UI 토글과 동일 키를 사용해야 실제로 연동됩니다.
class _DepartureRequestsViewWriteGate {
  static const String prefsKey = 'departure_requests_realtime_write_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
  }

  static Future<bool> canWrite() async {
    await _ensureLoaded();
    return _prefs!.getBool(prefsKey) ?? false; // 기본 OFF
  }
}

/// ✅ parking_requests_view "쓰기(Upsert/Delete)"를 기기 로컬 토글(SharedPreferences)로 제어
/// - 출차 요청/입차 완료 view와 동일 패턴
class _ParkingRequestsViewWriteGate {
  static const String prefsKey = 'parking_requests_realtime_write_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
  }

  static Future<bool> canWrite() async {
    await _ensureLoaded();
    return _prefs!.getBool(prefsKey) ?? false; // 기본 OFF
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

  /// ✅ (신규) 입차 요청 View 컬렉션명
  static const String _parkingRequestsViewCollection = 'parking_requests_view';

  /// ✅ plates 문서명과 동일한 docId를 항상 만들기 위한 헬퍼
  String _plateDocId(String plateNumber, String area) => '${plateNumber}_$area';

  /// ✅ view 문서는 area 1개(=parking_completed_view/{area})
  DocumentReference<Map<String, dynamic>> _parkingCompletedViewRef(String area) {
    return FirebaseFirestore.instance.collection(_parkingCompletedViewCollection).doc(area);
  }

  /// ✅ view 문서는 area 1개(=departure_requests_view/{area})
  DocumentReference<Map<String, dynamic>> _departureRequestsViewRef(String area) {
    return FirebaseFirestore.instance.collection(_departureRequestsViewCollection).doc(area);
  }

  /// ✅ view 문서는 area 1개(=parking_requests_view/{area})
  DocumentReference<Map<String, dynamic>> _parkingRequestsViewRef(String area) {
    return FirebaseFirestore.instance.collection(_parkingRequestsViewCollection).doc(area);
  }

  // ─────────────────────────────────────────
  // parking_completed_view upsert/remove
  // ─────────────────────────────────────────

  /// ✅ View upsert: parking_completed_view/{area}.items.{plateDocId}
  Future<void> _upsertParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    final canWriteView = await _ParkingCompletedViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_completed_view upsert (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _parkingCompletedViewRef(area);

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

  /// ✅ View remove: parking_completed_view/{area}.items.{plateDocId} delete
  Future<void> _removeParkingCompletedViewItem({
    required String area,
    required String plateDocId,
  }) async {
    final canWriteView = await _ParkingCompletedViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_completed_view remove (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _parkingCompletedViewRef(area);

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

  /// ✅ View upsert: departure_requests_view/{area}.items.{plateDocId}
  Future<void> _upsertDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    final canWriteView = await _DepartureRequestsViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip departure_requests_view upsert (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _departureRequestsViewRef(area);

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

  /// ✅ View remove: departure_requests_view/{area}.items.{plateDocId} delete
  Future<void> _removeDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
  }) async {
    final canWriteView = await _DepartureRequestsViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip departure_requests_view remove (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _departureRequestsViewRef(area);

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
  // parking_requests_view upsert/remove (신규)
  // ─────────────────────────────────────────

  /// ✅ View upsert: parking_requests_view/{area}.items.{plateDocId}
  Future<void> _upsertParkingRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    final canWriteView = await _ParkingRequestsViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_requests_view upsert (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _parkingRequestsViewRef(area);

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

  /// ✅ View remove: parking_requests_view/{area}.items.{plateDocId} delete
  Future<void> _removeParkingRequestsViewItem({
    required String area,
    required String plateDocId,
  }) async {
    final canWriteView = await _ParkingRequestsViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_requests_view remove (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _parkingRequestsViewRef(area);

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

  /// ✅ 로컬 SQLite: (필요 시) 입차완료 로그를 만들고 출차완료 처리까지 보장
  Future<void> _ensureLocalEntryAndMarkDepartureCompleted({
    required String plateNumber,
    required String location,
  }) async {
    await ParkingCompletedLogger.instance.maybeLogEntryCompleted(
      plateNumber: plateNumber,
      location: location,
      oldStatus: kStatusEntryRequest,
      newStatus: kStatusEntryDone,
    );

    await ParkingCompletedLogger.instance.markDepartureCompleted(
      plateNumber: plateNumber,
      location: location,
    );
  }

  /// 입차 완료 (parking_requests → parking_completed)
  Future<void> setParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

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

    // ✅ parking_requests 이탈 → parking_requests_view remove
    await _removeParkingRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
    );

    // ✅ parking_completed 진입 → parking_completed_view upsert
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );

    await ParkingCompletedLogger.instance.maybeLogEntryCompleted(
      plateNumber: plateNumber,
      location: location,
      oldStatus: kStatusEntryRequest,
      newStatus: kStatusEntryDone,
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

    // ✅ parking_completed 이탈 → parking_completed_view remove
    await _removeParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
    );

    // ✅ departure_requests 진입 → departure_requests_view upsert
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

    // ✅ parking_completed 이탈 → parking_completed_view remove
    await _removeParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
    );

    await _ensureLocalEntryAndMarkDepartureCompleted(
      plateNumber: plateNumber,
      location: location,
    );
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

    // ✅ departure_requests 이탈 → departure_requests_view remove
    await _removeDepartureRequestsViewItem(
      area: selectedPlate.area,
      plateDocId: plateDocId,
    );

    await ParkingCompletedLogger.instance.markDepartureCompleted(
      plateNumber: selectedPlate.plateNumber,
      location: selectedPlate.location,
    );
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

    // ✅ departure_requests 이탈 → departure_requests_view remove
    await _removeDepartureRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
    );

    // ✅ parking_completed 재진입 → parking_completed_view upsert
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );
  }

  /// (옵션) 임의 상태 → 입차 요청 되돌리기
  /// ✅ (요구사항) "입차 요청으로 되돌리면 parking_requests_view에 생성",
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

    // ✅ parking_requests 재진입 → parking_requests_view upsert
    await _upsertParkingRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: newLocation,
    );
  }
}
