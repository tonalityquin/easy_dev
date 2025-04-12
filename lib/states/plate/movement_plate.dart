import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import 'plate_state.dart';
import '../../models/plate_log_model.dart';
import '../../enums/plate_type.dart';
import 'log_plate.dart';

class MovementPlate {
  final PlateRepository _repository;
  final LogPlateState _logState;

  MovementPlate(this._repository, this._logState);

  Future<bool> _transferData({
    required PlateType fromType,
    required PlateType toType,
    required String plateNumber,
    required String area,
    required String location,
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
      final selectedBy = plateData['selectedBy'] ?? '시스템';

      // ✅ 변경된 필드만 업데이트
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

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: area,
          from: fromType.name,
          to: toType.name,
          action: toType.firestoreValue,
          performedBy: selectedBy,
          timestamp: DateTime.now(),
        ),
      );

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
    String location, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.parkingRequests,
      toType: PlateType.parkingCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> setDepartureRequested(
    String plateNumber,
    String area,
    PlateState plateState,
    String location, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.parkingCompleted,
      toType: PlateType.departureRequests,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> setDepartureCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.departureRequests,
      toType: PlateType.departureCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> setDepartureCompletedWithPlate(
    PlateModel plate,
    PlateState plateState,
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

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plate.plateNumber,
          area: plate.area,
          from: PlateType.departureRequests.name,
          to: PlateType.departureCompleted.name,
          action: PlateType.departureCompleted.firestoreValue,
          performedBy: plate.userName,
          timestamp: DateTime.now(),
        ),
      );

      await plateState.fetchPlateData();
    } catch (e) {
      debugPrint('🚨 출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  Future<void> doubleParkingCompletedToDepartureCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.parkingCompleted,
      toType: PlateType.departureCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );
    if (success) await plateState.fetchPlateData();
  }

  Future<void> doubleParkingCompletedToDepartureCompletedWithPlate(
    PlateModel plate,
    PlateState plateState,
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

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plate.plateNumber,
          area: plate.area,
          from: PlateType.parkingCompleted.name,
          to: PlateType.departureCompleted.name,
          action: PlateType.departureCompleted.firestoreValue,
          performedBy: plate.userName,
          timestamp: DateTime.now(),
        ),
      );

      await plateState.fetchPlateData();
    } catch (e) {
      debugPrint('🚨 출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  Future<void> goBackToParkingRequest({
    required PlateType fromType,
    required String plateNumber,
    required String area,
    required PlateState plateState,
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

      debugPrint("🔄 복원 완료 → ${PlateType.parkingRequests.name}: $plateNumber");

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: area,
          from: fromType.name,
          to: PlateType.parkingRequests.name,
          action: '입차 요청 복원',
          performedBy: performedBy,
          timestamp: DateTime.now(),
        ),
      );

      await plateState.fetchPlateData();
    } catch (e) {
      debugPrint("🚨 복원 오류: $e");
    }
  }

  Future<void> moveDepartureToParkingCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
    String location, {
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: PlateType.departureRequests,
      toType: PlateType.parkingCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );

    if (!success) {
      debugPrint("🚫 출차 요청 → 입차 완료 이동 실패");
    }
  }

  Future<void> updatePlateStatus({
    required PlateType fromType,
    required PlateType toType,
    required String plateNumber,
    required String area,
    required PlateState plateState,
    required String location,
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromType: fromType,
      toType: toType,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );

    if (success) await plateState.fetchPlateData();
  }
}
