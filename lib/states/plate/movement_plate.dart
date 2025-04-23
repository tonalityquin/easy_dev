import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import 'plate_state.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../../utils/gcs_uploader.dart';

class MovementPlate {
  final PlateRepository _repository;

  MovementPlate(this._repository);

  final _uploader = GCSUploader();

  Future<bool> _transferData({
    required PlateType fromType,
    required PlateType toType,
    required String plateNumber,
    required String area,
    required String location,
    required String division,
    String performedBy = '시스템',
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      final document = await _repository.getPlate(documentId);
      if (document == null) {
        debugPrint("🚫 [${fromType.name}] 문서를 찾을 수 없음: $documentId");
        return false;
      }

      final plateData = document.toMap();
      final selectedBy = plateData['selectedBy'] ?? performedBy;

      final updateData = {
        'type': toType.firestoreValue,
        'location': location,
        'userName': selectedBy,
        'isSelected': false,
        'selectedBy': null,
        if (toType == PlateType.departureCompleted) 'end_time': DateTime.now(),
      };

      await _repository.updatePlate(documentId, updateData);
      debugPrint("✅ 문서 상태 이동 완료: ${fromType.name} → ${toType.name} ($plateNumber)");

      final log = PlateLogModel(
        plateNumber: plateNumber,
        area: area,
        from: fromType.name,
        to: toType.name,
        action: '${fromType.label} → ${toType.label}',
        performedBy: selectedBy,
        timestamp: DateTime.now(),
      );
      await _uploader.uploadLogJson(log.toMap(), plateNumber, division, area);

      return true;
    } catch (e) {
      debugPrint('🚨 문서 상태 이동 오류: $e');
      return false;
    }
  }

  Future<void> setParkingCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location,
    String division, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.parkingRequests,
      toType: PlateType.parkingCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      division: division,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> setDepartureRequested(
    String plateNumber,
    String area,
    PlateState plateState,
    String location,
    String division, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.parkingCompleted,
      toType: PlateType.departureRequests,
      plateNumber: plateNumber,
      area: area,
      location: location,
      division: division,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> setDepartureCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location,
    String division, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.departureRequests,
      toType: PlateType.departureCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      division: division,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> doubleParkingCompletedToDepartureCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location,
    String division, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.parkingCompleted,
      toType: PlateType.departureCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      division: division,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> goBackToParkingRequest({
    required PlateType fromType,
    required String plateNumber,
    required String area,
    required PlateState plateState,
    required String division,
    String newLocation = "미지정",
    String performedBy = '시스템',
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      final document = await _repository.getPlate(documentId);
      if (document == null) {
        debugPrint("🚫 문서를 찾을 수 없음: $documentId");
        return;
      }

      await _repository.deletePlate(documentId);

      final updatedPlate = document.copyWith(
        location: newLocation,
        type: PlateType.parkingRequests.firestoreValue,
        isSelected: false,
        selectedBy: null,
      );

      await _repository.addOrUpdatePlate(documentId, updatedPlate);
      await plateState.fetchPlateData();

      final log = PlateLogModel(
        plateNumber: plateNumber,
        area: area,
        from: fromType.name,
        to: PlateType.parkingRequests.name,
        action: '${fromType.label} → ${PlateType.parkingRequests.label}',
        performedBy: performedBy,
        timestamp: DateTime.now(),
      );
      await _uploader.uploadLogJson(log.toMap(), plateNumber, division, area);
    } catch (e) {
      debugPrint("🚨 복원 오류: $e");
    }
  }

  Future<void> moveDepartureToParkingCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location,
    String division, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.departureRequests,
      toType: PlateType.parkingCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      division: division,
      performedBy: performedBy,
    );
    if (success) {
      await plateState.fetchPlateData();
    } else {
      debugPrint("🚫 출차 요청 → 입차 완료 이동 실패");
    }
  }

  Future<void> setDepartureCompletedWithPlate(
    PlateModel plate,
    PlateState plateState,
    String division,
  ) async {
    final documentId = '${plate.plateNumber}_${plate.area}';

    try {
      await _repository.deletePlate(documentId);

      final updatedPlate = plate.copyWith(
        type: PlateType.departureCompleted.firestoreValue,
        location: plate.location,
        userName: plate.userName,
        isSelected: false,
        selectedBy: null,
        endTime: DateTime.now(),
      );

      await _repository.addOrUpdatePlate(documentId, updatedPlate);
      await plateState.fetchPlateData();

      final log = PlateLogModel(
        plateNumber: plate.plateNumber,
        area: plate.area,
        from: PlateType.departureRequests.name,
        to: PlateType.departureCompleted.name,
        action: '출차 요청 → 출차 완료',
        performedBy: plate.userName,
        timestamp: DateTime.now(),
      );
      await _uploader.uploadLogJson(log.toMap(), plate.plateNumber, division, plate.area);
    } catch (e) {
      debugPrint('🚨 출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  Future<void> doubleParkingCompletedToDepartureCompletedWithPlate(
    PlateModel plate,
    PlateState plateState,
    String division,
  ) async {
    final documentId = '${plate.plateNumber}_${plate.area}';

    try {
      await _repository.deletePlate(documentId);

      final updatedPlate = plate.copyWith(
        type: PlateType.departureCompleted.firestoreValue,
        location: plate.location,
        userName: plate.userName,
        isSelected: false,
        selectedBy: null,
        endTime: DateTime.now(),
      );

      await _repository.addOrUpdatePlate(documentId, updatedPlate);
      await plateState.fetchPlateData();

      final log = PlateLogModel(
        plateNumber: plate.plateNumber,
        area: plate.area,
        from: PlateType.parkingCompleted.name,
        to: PlateType.departureCompleted.name,
        action: '입차 완료 → 출차 완료',
        performedBy: plate.userName,
        timestamp: DateTime.now(),
      );
      await _uploader.uploadLogJson(log.toMap(), plate.plateNumber, division, plate.area);
    } catch (e) {
      debugPrint('🚨 출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  Future<void> updatePlateStatus({
    required PlateType fromType,
    required PlateType toType,
    required String plateNumber,
    required String area,
    required PlateState plateState,
    required String location,
    required String division,
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: fromType,
      toType: toType,
      plateNumber: plateNumber,
      area: area,
      location: location,
      division: division,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }
}
