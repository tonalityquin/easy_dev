import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate_repo_services/plate_repository.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../../utils/usage_reporter.dart';

class MovementPlate {
  final PlateRepository _repository;
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

      // 🧭 UsageReporter: Firestore 쓰기 1회 기록
      UsageReporter.instance.report(
        area: plate.area,
        action: 'write',
        n: 1,
        source: 'MovementPlate.setDepartureCompleted',
      );
    } catch (e) {
      debugPrint('출차 완료 이동 실패: $e');
      // 실패 계측(선택)
      // UsageReporter.instance.report(
      //   area: plate.area,
      //   action: 'write_failed',
      //   n: 1,
      //   source: 'MovementPlate.setDepartureCompleted',
      // );
      rethrow;
    }
  }

  /// ✅ (바로) 입차 완료 → 출차 완료 점프 전환
  /// - transitionPlateState 이후에 선택 해제를 **추가 보장** (레포 함수 시그니처상 필드 병합이 어려운 경우 대비)
  Future<void> jumpingDepartureCompleted(PlateModel plate) async {
    final documentId = '${plate.plateNumber}_${plate.area}';

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

      // 상태 전환 (WRITE 1)
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: PlateType.departureCompleted,
        location: plate.location,
        userName: plate.userName,
        includeEndTime: true,
        log: log,
      );

      UsageReporter.instance.report(
        area: plate.area,
        action: 'write',
        n: 1,
        source: 'MovementPlate.jumpingDepartureCompleted.transition',
      );

      // ✅ 선택 해제(핵심) — 전환 직후 보강 업데이트 (WRITE 1)
      await _repository.updatePlate(documentId, {
        PlateFields.isSelected: false,
        PlateFields.selectedBy: FieldValue.delete(),
        PlateFields.updatedAt: Timestamp.now(),
      });

      UsageReporter.instance.report(
        area: plate.area,
        action: 'write',
        n: 1,
        source: 'MovementPlate.jumpingDepartureCompleted.unselect',
      );

      debugPrint("출차 완료 상태로 업데이트 완료: $documentId");
    } catch (e) {
      debugPrint('출차 완료 업데이트 실패: $e');
      // 실패 계측(선택)
      // UsageReporter.instance.report(
      //   area: plate.area,
      //   action: 'write_failed',
      //   n: 1,
      //   source: 'MovementPlate.jumpingDepartureCompleted',
      // );
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

    try {
      // READ 1: 현재 문서 가져오기
      final document = await _repository.getPlate(documentId);
      UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'MovementPlate._transferData.getPlate',
      );

      if (document == null) {
        return false;
      }

      final selectedBy = document.selectedBy ?? performedBy;

      // 이동 로그
      final log = PlateLogModel(
        plateNumber: plateNumber,
        type: toType.firestoreValue, // e.g. 'parking_completed' / 'departure_completed'
        area: area,
        from: fromType.label, // 사람이 읽는 전 상태
        to: toType.label, // 사람이 읽는 후 상태
        action: '${fromType.label} → ${toType.label}',
        performedBy: selectedBy,
        timestamp: DateTime.now(),
      );

      // 상태 전환 (WRITE 1)
      await _repository.transitionPlateState(
        documentId: documentId,
        toType: toType,
        location: location,
        userName: selectedBy,
        includeEndTime: toType == PlateType.departureCompleted,
        log: log,
      );

      UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'MovementPlate._transferData.transition',
      );

      // ✅ 도착 상태가 '출차 완료'라면, 선택 해제 보장(추가 WRITE 1)
      if (toType == PlateType.departureCompleted) {
        try {
          await _repository.updatePlate(documentId, {
            PlateFields.isSelected: false,
            PlateFields.selectedBy: FieldValue.delete(),
            PlateFields.updatedAt: Timestamp.now(),
          });

          UsageReporter.instance.report(
            area: area,
            action: 'write',
            n: 1,
            source: 'MovementPlate._transferData.unselect',
          );
        } catch (e) {
          // 선택 해제 보강 실패는 치명적이지 않으므로 warn 로깅
          debugPrint('선택 해제 보강 실패: $e');
          // 실패 계측(선택)
          // UsageReporter.instance.report(
          //   area: area,
          //   action: 'write_failed',
          //   n: 1,
          //   source: 'MovementPlate._transferData.unselect',
          // );
        }
      }

      return true;
    } catch (e) {
      debugPrint('문서 상태 이동 오류: $e');
      // 실패 계측(선택)
      // UsageReporter.instance.report(
      //   area: area,
      //   action: 'write_failed',
      //   n: 1,
      //   source: 'MovementPlate._transferData',
      // );
      return false;
    }
  }
}
