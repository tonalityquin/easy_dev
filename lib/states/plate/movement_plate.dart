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

class MovementPlate extends ChangeNotifier {
  final PlateWriteService _write;
  final UserState _user;

  MovementPlate(this._write, this._user);

  /// ✅ (변경) 2안용: 경량 View 컬렉션명
  static const String _parkingCompletedViewCollection = 'parking_completed_view';

  /// ✅ plates 문서명과 동일한 docId를 항상 만들기 위한 헬퍼
  String _plateDocId(String plateNumber, String area) => '${plateNumber}_$area';

  /// ✅ (변경) view 문서는 area 1개(=parking_completed_view/{area})
  DocumentReference<Map<String, dynamic>> _viewRef(String area) {
    return FirebaseFirestore.instance.collection(_parkingCompletedViewCollection).doc(area);
  }

  /// ✅ (변경) View upsert: area 문서의 items.{plateDocId}에 경량 데이터 저장
  Future<void> _upsertParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) async {
    // ✅ (핵심) 토글 OFF면 view 쓰기 자체를 수행하지 않음
    final canWriteView = await _ParkingCompletedViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_completed_view upsert (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _viewRef(area);

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
      // view는 조회용 보조 인덱스 성격이므로 실패해도 본 흐름/SQLite는 유지
      debugPrint('⚠️ parking_completed_view upsert 실패: $e');
    }
  }

  /// ✅ (변경) View remove: area 문서의 items.{plateDocId} 삭제
  Future<void> _removeParkingCompletedViewItem({
    required String area,
    required String plateDocId,
  }) async {
    // ✅ (핵심) 토글 OFF면 view 쓰기(삭제)도 수행하지 않음
    final canWriteView = await _ParkingCompletedViewWriteGate.canWrite();
    if (!canWriteView) {
      if (kDebugMode) {
        debugPrint('🚫 [MovementPlate] skip parking_completed_view remove (toggle OFF)');
      }
      return;
    }

    try {
      final ref = _viewRef(area);

      // set(merge)에서 FieldValue.delete()를 사용해 단일 write로 처리
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

  /// ✅ 로컬 SQLite: (필요 시) 입차완료 로그를 만들고 출차완료 처리까지 보장
  /// - status_mapping.dart 상수(kStatusEntryRequest/kStatusEntryDone) 및 ParkingCompletedLogger 적용
  Future<void> _ensureLocalEntryAndMarkDepartureCompleted({
    required String plateNumber,
    required String location,
  }) async {
    // (1) 혹시 이 기기 로컬에 입차완료 로그가 없는 경우 대비: 있으면 skip될 수 있도록 maybeLog 사용
    await ParkingCompletedLogger.instance.maybeLogEntryCompleted(
      plateNumber: plateNumber,
      location: location,
      oldStatus: kStatusEntryRequest,
      newStatus: kStatusEntryDone,
    );

    // (2) 출차 완료 플래그 ON
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

    // 1) Firestore 타입 전환 + location/area 업데이트
    // ✅ (추가) plates에도 parkingCompletedAt 기록(정합성)
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

    // 2) ✅ Firestore view 동기화(입차 완료 진입): 토글 ON일 때만 실제 upsert
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );

    // 3) 로컬 SQLite ParkingCompleted에 즉시 기록 (기존 유지)
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
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    // ✅ parking_completed 이탈 → 토글 ON일 때만 view(area 문서)에서 해당 item 제거
    await _removeParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
    );

    // 출차 요청 자체는 로컬 ParkingCompleted에 별도 변동 없음 (기존 유지)
  }

  /// ✅ (신규) 출차 완료 "직접" 처리 (parking_completed → departure_completed)
  ///
  /// - Firestore 타입 전환: parking_completed → departure_completed
  /// - parking_completed_view에서는 해당 item 제거(토글 ON인 경우)
  /// - 로컬 SQLite: (필요 시) 입차완료 로그 생성 후 출차완료로 마킹
  Future<void> setDepartureCompletedDirectFromParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateDocId = _plateDocId(plateNumber, area);

    // 1) Firestore: parking_completed -> departure_completed 직접 전환
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

    // 2) View: parking_completed 이탈이므로 제거(토글 ON일 때만)
    await _removeParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
    );

    // 3) 로컬 SQLite: 출차 완료 플래그 ON (입차완료 로그 없으면 만들어 둔 뒤 처리)
    await _ensureLocalEntryAndMarkDepartureCompleted(
      plateNumber: plateNumber,
      location: location,
    );
  }

  /// 출차 완료 (departure_requests → departure_completed)
  ///
  /// - Firestore 타입 전환
  /// - 로컬 SQLite에서는 해당 차량의 가장 최근 미출차 기록을 "출차 완료"로 표시
  Future<void> setDepartureCompleted(
      PlateModel selectedPlate, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;

    // ✅ selectedPlate.id가 비어있을 가능성까지 방어(원칙적으로는 plates docId)
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

    // ✅ 로컬 SQLite: 출차 완료 플래그 ON (기존 유지)
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

    // ✅ 입차 완료 재진입 → 토글 ON일 때만 view(area 문서)에 item upsert
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
    );

    // SQLite에 추가 로그를 남길지 여부는 기존 정책대로(여기서는 기존 코드 유지: 호출 없음)
  }

  /// (옵션) 임의 상태 → 입차 요청 되돌리기
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
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );

    // ✅ parking_completed에서 이탈하는 경우에만(그리고 토글 ON일 때만) view 정리
    if (fromType == PlateType.parkingCompleted) {
      await _removeParkingCompletedViewItem(
        area: area,
        plateDocId: plateDocId,
      );
    }

    // 입차 요청 상태로 되돌리는 건 로컬 ParkingCompleted 대상 아님 (기존 유지)
  }
}
