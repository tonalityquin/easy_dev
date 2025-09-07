import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../screens/type_package/debugs/firestore_logger.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';

class MovementPlate {
  final PlateRepository _repository;
  final _logger = FirestoreLogger();

  MovementPlate(this._repository);

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

  /// ✅ 출차 완료 (개별 PlateModel 기반)
  /// - 상태 전환과 함께 선택 해제(isSelected=false, selectedBy 삭제)를 **동일 트랜잭션 수준**으로 업데이트
  Future<void> setDepartureCompleted(PlateModel plate) async {
    final documentId = '${plate.plateNumber}_${plate.area}';
    await _logger.log('[MovementPlate] setDepartureCompleted 시작: $documentId', level: 'called');

    try {
      final now = DateTime.now();

      // ✅ 상태 전환 + 선택 해제 + 종료시간/업데이트시간 동시 반영
      final updateFields = {
        // 상태 전환
        PlateFields.type: PlateType.departureCompleted.firestoreValue,

        // 위치/시간 업데이트
        PlateFields.location: plate.location,
        PlateFields.endTime: now,
        PlateFields.updatedAt: Timestamp.now(),

        // ✅ 선택 해제(핵심)
        PlateFields.isSelected: false,
        PlateFields.selectedBy: FieldValue.delete(),
      };

      final log = PlateLogModel(
        plateNumber: plate.plateNumber,
        type: PlateType.departureCompleted.firestoreValue,
        area: plate.area,
        from: PlateType.departureRequests.label,
        to: PlateType.departureCompleted.label,
        action: '출차 요청 → 출차 완료',
        performedBy: plate.userName,
        timestamp: now,
        billingType: plate.billingType,
      );

      await _repository.updatePlate(documentId, updateFields, log: log);

      await _logger.log('출차 완료 업데이트 Firestore 완료: $documentId', level: 'success');
    } catch (e) {
      await _logger.log('출차 완료 이동 실패: $e', level: 'error');
      debugPrint('출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  /// ✅ (바로) 입차 완료 → 출차 완료 점프 전환
  /// - transitionPlateState 이후에 선택 해제를 **추가 보장** (레포 함수 시그니처상 필드 병합이 어려운 경우 대비)
  Future<void> jumpingDepartureCompleted(PlateModel plate) async {
    final documentId = '${plate.plateNumber}_${plate.area}';
    await _logger.log('[MovementPlate] jumpingDepartureCompleted 시작: $documentId', level: 'called');

    try {
      final log = PlateLogModel(
        plateNumber: plate.plateNumber,
        type: PlateType.departureCompleted.firestoreValue,
        area: plate.area,
        from: PlateType.parkingCompleted.name,
        to: PlateType.departureCompleted.name,
        action: '입차 완료 → 출차 완료',
        performedBy: plate.userName,
        timestamp: DateTime.now(),
      );

      // 상태 전환
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: PlateType.departureCompleted,
        location: plate.location,
        userName: plate.userName,
        includeEndTime: true,
        log: log,
      );

      // ✅ 선택 해제(핵심) — 전환 직후 보강 업데이트
      await _repository.updatePlate(documentId, {
        PlateFields.isSelected: false,
        PlateFields.selectedBy: FieldValue.delete(),
        PlateFields.updatedAt: Timestamp.now(),
      });

      await _logger.log('입차 완료 → 출차 완료 업데이트 완료(선택 해제 포함): $documentId', level: 'success');
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

  /// 공통 상태 전환 함수
  /// - 기본적으로 transitionPlateState를 사용
  /// - ✅ toType이 `departureCompleted`인 경우 선택 해제를 **추가 보장**
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

      // 이동 로그
      final log = PlateLogModel(
        plateNumber: plateNumber,
        type: toType.firestoreValue,     // e.g. 'parking_completed' / 'departure_completed'
        area: area,
        from: fromType.label,            // 사람이 읽는 전 상태
        to: toType.label,                // 사람이 읽는 후 상태
        action: '${fromType.label} → ${toType.label}',
        performedBy: selectedBy,
        timestamp: DateTime.now(),
      );

      // 상태 전환
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: toType,
        location: location,
        userName: selectedBy,
        includeEndTime: toType == PlateType.departureCompleted,
        log: log,
      );

      // ✅ 도착 상태가 '출차 완료'라면, 선택 해제 보장(핵심 수정)
      if (toType == PlateType.departureCompleted) {
        try {
          await _repository.updatePlate(documentId, {
            PlateFields.isSelected: false,
            PlateFields.selectedBy: FieldValue.delete(),
            PlateFields.updatedAt: Timestamp.now(),
          });
        } catch (e) {
          // 선택 해제 보강 실패는 치명적이지 않으므로 warn로깅
          await _logger.log('선택 해제 보강 실패(무시 가능): $e', level: 'warn');
        }
      }

      await _logger.log('문서 상태 이동 완료: $fromType → $toType ($plateNumber)', level: 'success');
      return true;
    } catch (e) {
      await _logger.log('상태 이동 오류: $e', level: 'error');
      debugPrint('문서 상태 이동 오류: $e');
      return false;
    }
  }
}
