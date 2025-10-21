import 'package:flutter/foundation.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_write_service.dart';
import '../../screens/type_package/parking_completed_package/services/local_transition_guard.dart';
import '../../screens/type_package/parking_completed_package/services/parking_completed_logger.dart';
import '../../screens/type_package/parking_completed_package/services/status_mapping.dart';
import '../user/user_state.dart';
// import '../../utils/usage_reporter.dart';

// ▼ 로거/상태/가드


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

    await _write.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: PlateType.parkingRequests.firestoreValue,
      toType: PlateType.parkingCompleted.firestoreValue,
      extraFields: {'location': location, 'area': area},
      forceOverride: forceOverride,
    );

    // ✅ 내 단말: 즉시 로깅 + 스트림 재유입 중복 방지 마킹
    await ParkingCompletedLogger.instance.maybeLogCompleted(
      plateNumber: plateNumber,
      area: area,
      oldStatus: kStatusEntryRequest,
      newStatus: kStatusEntryDone,
    );
    LocalTransitionGuard.instance.markUserParkingCompleted(
      plateNumber: plateNumber,
      area: area,
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
      extraFields: {'location': location, 'area': area},
      forceOverride: forceOverride,
    );
  }

  /// 출차 완료 (departure_requests → departure_completed)
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
  }

  /// (옵션) 출차 요청 → 입차 완료 되돌리기
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
      extraFields: {'area': area, 'location': location},
      forceOverride: forceOverride,
    );

    // ✅ 내 단말: 즉시 로깅 + 스트림 재유입 중복 방지 마킹
    await ParkingCompletedLogger.instance.maybeLogCompleted(
      plateNumber: plateNumber,
      area: area,
      oldStatus: kStatusExitRequest,
      newStatus: kStatusEntryDone,
    );
    LocalTransitionGuard.instance.markUserParkingCompleted(
      plateNumber: plateNumber,
      area: area,
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
      extraFields: {'area': area, 'location': newLocation},
      forceOverride: forceOverride,
    );
  }
}
