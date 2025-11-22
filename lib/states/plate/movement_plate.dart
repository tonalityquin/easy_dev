// lib/states/plate/movement_plate.dart

import 'package:flutter/foundation.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_write_service.dart';
import '../../screens/type_package/parking_completed_package/table_package/services/parking_completed_logger.dart';
import '../../screens/type_package/parking_completed_package/table_package/services/status_mapping.dart';
import '../user/user_state.dart';

// 🔹 입차/출차 로컬 SQLite 기록용


class MovementPlate extends ChangeNotifier {
  final PlateWriteService _write;
  final UserState _user;

  MovementPlate(this._write, this._user);

  /// 입차 완료 (parking_requests → parking_completed)
  Future<void> setParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateId = '${plateNumber}_$area';

    // 1) Firestore 타입 전환 + location/area 업데이트
    await _write.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: PlateType.parkingRequests.firestoreValue,
      toType: PlateType.parkingCompleted.firestoreValue,
      extraFields: {
        'location': location,
        'area': area,
      },
      forceOverride: forceOverride,
    );

    // 2) 로컬 SQLite ParkingCompleted에 즉시 기록
    await ParkingCompletedLogger.instance.maybeLogEntryCompleted(
      plateNumber: plateNumber,
      location: location,          // 주차 구역을 location 컬럼으로 저장
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
    final plateId = '${plateNumber}_$area';

    await _write.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: PlateType.parkingCompleted.firestoreValue,
      toType: PlateType.departureRequests.firestoreValue,
      extraFields: {
        'location': location,
        'area': area,
      },
      forceOverride: forceOverride,
    );

    // 출차 요청 자체는 로컬 ParkingCompleted에 별도 변동 없음
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
    final plateId = selectedPlate.id;

    await _write.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: PlateType.departureRequests.firestoreValue,
      toType: PlateType.departureCompleted.firestoreValue,
      extraFields: {
        'area': selectedPlate.area,
        'location': selectedPlate.location,
      },
      forceOverride: forceOverride,
    );

    // ✅ 로컬 SQLite: 출차 완료 플래그 ON
    await ParkingCompletedLogger.instance.markDepartureCompleted(
      plateNumber: selectedPlate.plateNumber,
      location: selectedPlate.location,
    );
  }

  /// (옵션) 출차 요청 → 입차 완료 되돌리기
  ///
  /// - 이 경우는 "입차 완료 기록 추가"로 보고 싶다면
  ///   아래에서 maybeLogEntryCompleted 를 호출하면 되고,
  ///   아니면 호출하지 않으면 됨.
  Future<void> goBackToParkingCompleted(
      String plateNumber,
      String area,
      String location, {
        bool forceOverride = true,
      }) async {
    final actor = _user.name;
    final plateId = '${plateNumber}_$area';

    await _write.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: PlateType.departureRequests.firestoreValue,
      toType: PlateType.parkingCompleted.firestoreValue,
      extraFields: {
        'area': area,
        'location': location,
      },
      forceOverride: forceOverride,
    );
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
    final plateId = '${plateNumber}_$area';

    await _write.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: fromType.firestoreValue,
      toType: PlateType.parkingRequests.firestoreValue,
      extraFields: {
        'area': area,
        'location': newLocation,
      },
      forceOverride: forceOverride,
    );

    // 입차 요청 상태로 되돌리는 건 로컬 ParkingCompleted 대상 아님
  }
}
