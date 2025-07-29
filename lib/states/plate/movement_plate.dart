import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../area/area_state.dart';

class MovementPlate {
  final PlateRepository _repository;
  final AreaState _areaState;
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
      // 출차 완료 상태로 필드 업데이트
      final updateFields = {
        'type': PlateType.departureCompleted.firestoreValue,
        'location': plate.location,
        'endTime': DateTime.now(),
        'updatedAt': Timestamp.now(),
      };

      // 로그 생성
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

      // Firestore 로그 누적 포함하여 문서 업데이트
      await _repository.updatePlate(documentId, updateFields, log: log);

      await _logger.log('출차 완료 업데이트 Firestore 완료: $documentId', level: 'success');
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
      // 로그 생성
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

      // 상태 전이 + 로그 삽입 포함된 업데이트
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: PlateType.departureCompleted,
        location: plate.location,
        userName: plate.userName,
        includeEndTime: true,
        log: log, // 🔹 로그 전달
      );

      await _logger.log('입차 완료 → 출차 완료 업데이트 완료: $documentId', level: 'success');

      // 🔒 요금 고정 시 summary log 필요 시 Firestore 버전으로 구현
      // if (plate.isLockedFee == true) {
      //   await _repository.uploadSummaryLog(...) 또는 별도 구현
      // }

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
    required String performedBy,
  }) async {
    await _transferData(
      fromType: fromType,
      toType: PlateType.parkingRequests,
      plateNumber: plateNumber,
      area: area,
      location: newLocation,
      performedBy: performedBy,
    );
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

      // ✅ Firestore logs 필드에 로그 누적
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: toType,
        location: location,
        userName: selectedBy,
        includeEndTime: toType == PlateType.departureCompleted,
        log: log, // 로그 전달
      );

      await _logger.log('문서 상태 이동 완료: $fromType → $toType ($plateNumber)', level: 'success');

      return true;
    } catch (e) {
      await _logger.log('상태 이동 오류: $e', level: 'error');
      debugPrint('문서 상태 이동 오류: $e');
      return false;
    }
  }
}
