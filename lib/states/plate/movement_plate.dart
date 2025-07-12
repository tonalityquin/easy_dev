import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';
import '../../utils/gcs_json_uploader.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../area/area_state.dart';

class MovementPlate {
  final PlateRepository _repository;
  final AreaState _areaState;
  final _uploader = GcsJsonUploader();
  final _logger = FirestoreLogger();

  MovementPlate(this._repository, this._areaState);

  Future<void> setParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    String performedBy = '시스템',
  }) async {
    await _transferData(
      fromType: PlateType.parkingRequests,
      toType: PlateType.parkingCompleted,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );
  }

  Future<void> setDepartureRequested(
    String plateNumber,
    String area,
    String location, {
    String performedBy = '시스템',
  }) async {
    await _transferData(
      fromType: PlateType.parkingCompleted,
      toType: PlateType.departureRequests,
      plateNumber: plateNumber,
      area: area,
      location: location,
      performedBy: performedBy,
    );
  }

  Future<void> setDepartureCompleted(PlateModel plate) async {
    final documentId = '${plate.plateNumber}_${plate.area}';
    await _logger.log('[MovementPlate] setDepartureCompleted 시작: $documentId', level: 'called');

    try {
      await _repository.updateToDepartureCompleted(documentId, plate);
      await _logger.log('출차 완료 업데이트 Firestore 완료: $documentId', level: 'success');

      final log = PlateLogModel(
        plateNumber: plate.plateNumber,
        division: _areaState.currentDivision,
        area: plate.area,
        from: PlateType.departureRequests.name,
        to: PlateType.departureCompleted.name,
        action: '출차 요청 → 출차 완료',
        performedBy: plate.userName,
        timestamp: DateTime.now(),
      );

      await _uploader.uploadForPlateLogTypeJson(
        log.toMap()..removeWhere((k, v) => v == null),
        plate.plateNumber,
        _areaState.currentDivision,
        plate.area,
      );

      if (plate.isLockedFee == true) {
        await _uploader.mergeAndSummarizeLogs(
          plate.plateNumber,
          _areaState.currentDivision,
          plate.area,
        );
      }
    } catch (e) {
      await _logger.log('출차 완료 이동 실패: $e', level: 'error');
      debugPrint('출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  Future<void> jumpingDepartureCompleted(PlateModel plate) async {
    final documentId = '${plate.plateNumber}_${plate.area}';
    await _logger.log('[MovementPlate] jumpingDepartureCompleted 시작: $documentId', level: 'called');

    try {
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: PlateType.departureCompleted,
        location: plate.location,
        userName: plate.userName,
        includeEndTime: true,
      );

      await _logger.log('입차 완료 → 출차 완료 업데이트 완료: $documentId', level: 'success');

      final log = PlateLogModel(
        plateNumber: plate.plateNumber,
        division: _areaState.currentDivision,
        area: plate.area,
        from: PlateType.parkingCompleted.name,
        to: PlateType.departureCompleted.name,
        action: '입차 완료 → 출차 완료',
        performedBy: plate.userName,
        timestamp: DateTime.now(),
      );

      await _uploader.uploadForPlateLogTypeJson(
        log.toMap()..removeWhere((k, v) => v == null),
        plate.plateNumber,
        _areaState.currentDivision,
        plate.area,
      );

      if (plate.isLockedFee == true) {
        await _uploader.mergeAndSummarizeLogs(
          plate.plateNumber,
          _areaState.currentDivision,
          plate.area,
        );
      }

      debugPrint("출차 완료 상태로 업데이트 완료: $documentId");
    } catch (e) {
      await _logger.log('출차 완료 업데이트 실패: $e', level: 'error');
      debugPrint('출차 완료 업데이트 실패: $e');
      rethrow;
    }
  }

  Future<void> goBackToParkingCompleted(
    String plateNumber,
    String area,
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
      debugPrint("출차 요청 → 입차 완료 이동 실패");
    }
  }

  Future<void> goBackToParkingRequest({
    required PlateType fromType,
    required String plateNumber,
    required String area,
    required String newLocation,
    required String performedBy, // ✅ 필수 인자로 변경
  }) async {
    final documentId = '${plateNumber}_$area';
    await _logger.log('[MovementPlate] goBackToParkingRequest 시작: $documentId', level: 'called');

    try {
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: PlateType.parkingRequests,
        location: newLocation,
        userName: performedBy, // ✅ 작업자 기록
      );

      await _logger.log('상태 복원 완료 (Firestore): $documentId', level: 'success');

      final log = PlateLogModel(
        plateNumber: plateNumber,
        division: _areaState.currentDivision,
        area: area,
        from: fromType.name,
        to: PlateType.parkingRequests.name,
        action: '${fromType.label} → ${PlateType.parkingRequests.label}',
        performedBy: performedBy,
        // ✅ 시스템이 아닌 실제 사용자로 기록됨
        timestamp: DateTime.now(),
      );

      await _uploader.uploadForPlateLogTypeJson(
        log.toMap()..removeWhere((k, v) => v == null),
        plateNumber,
        _areaState.currentDivision,
        area,
      );

      debugPrint("상태 복원 완료: $documentId");
    } catch (e) {
      await _logger.log('상태 복원 실패: $e', level: 'error');
      debugPrint("복원 오류: $e");
    }
  }

  Future<bool> _transferData({
    required PlateType fromType,
    required PlateType toType,
    required String plateNumber,
    required String area,
    required String location,
    String performedBy = '시스템',
  }) async {
    final documentId = '${plateNumber}_$area';
    await _logger.log('[MovementPlate] _transferData 시작: $fromType → $toType | 문서ID: $documentId', level: 'called');

    try {
      final document = await _repository.getPlate(documentId);
      if (document == null) {
        await _logger.log('문서를 찾을 수 없음: $documentId', level: 'warn');
        return false;
      }

      final selectedBy = document.selectedBy ?? performedBy;

      await _repository.transitionPlateState(
        documentId: documentId,
        toType: toType,
        location: location,
        userName: selectedBy,
        includeEndTime: toType == PlateType.departureCompleted,
      );

      await _logger.log('문서 상태 이동 완료: $fromType → $toType ($plateNumber)', level: 'success');

      final log = PlateLogModel(
        plateNumber: plateNumber,
        division: _areaState.currentDivision,
        area: area,
        from: fromType.name,
        to: toType.name,
        action: '${fromType.label} → ${toType.label}',
        performedBy: selectedBy,
        timestamp: DateTime.now(),
      );

      await _uploader.uploadForPlateLogTypeJson(
        log.toMap()..removeWhere((k, v) => v == null),
        plateNumber,
        _areaState.currentDivision,
        area,
      );

      return true;
    } catch (e) {
      await _logger.log('상태 이동 오류: $e', level: 'error');
      debugPrint('문서 상태 이동 오류: $e');
      return false;
    }
  }
}
