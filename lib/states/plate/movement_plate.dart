import 'package:flutter/foundation.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_write_service.dart';
// 로컬 로깅/가드 관련 import 제거
// import '../../screens/type_package/parking_completed_package/services/local_transition_guard.dart';
// import '../../screens/type_package/parking_completed_package/services/parking_completed_logger.dart';
// import '../../screens/type_package/parking_completed_package/services/status_mapping.dart';
import '../user/user_state.dart';

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

    // ✅ 로깅은 PlateStreamService에서만 수행(단일화)
    // (여기서 즉시 SQLite 기록/가드 마킹을 하지 않습니다)
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

    // ✅ 로깅은 PlateStreamService에서만 수행(단일화)
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
