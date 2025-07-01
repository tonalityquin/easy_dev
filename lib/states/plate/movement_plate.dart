import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../utils/gcs_json_uploader.dart';
import 'plate_state.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../area/area_state.dart';

class MovementPlate {
  // 🔹 1. 필드
  final PlateRepository _repository;
  final AreaState _areaState;
  final _uploader = GcsJsonUploader();

  // 🔹 2. 생성자
  MovementPlate(this._repository, this._areaState);

  // 🔹 3. Public 메서드

  Future<void> setParkingCompleted(
      String plateNumber,
      String area,
      PlateState plateState,
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
      PlateState plateState,
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

  Future<void> setDepartureCompleted(
      PlateModel plate,
      PlateState plateState,
      ) async {
    final documentId = '${plate.plateNumber}_${plate.area}';

    try {
      final updateData = {
        'type': PlateType.departureCompleted.firestoreValue,
        'location': plate.location,
        'userName': plate.userName,
        'isSelected': false,
        'selectedBy': null,
        'updatedAt': Timestamp.now(),
        'end_time': DateTime.now(),
        if (plate.isLockedFee == true) 'isLockedFee': true,
        if (plate.lockedAtTimeInSeconds != null) 'lockedAtTimeInSeconds': plate.lockedAtTimeInSeconds,
        if (plate.lockedFeeAmount != null) 'lockedFeeAmount': plate.lockedFeeAmount,
      };

      await _repository.updatePlate(documentId, updateData);

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

      final logMap = log.toMap()..removeWhere((k, v) => v == null);

      await _uploader.uploadForPlateLogTypeJson(
        logMap,
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
      debugPrint('🚨 출차 완료 이동 실패: $e');
      rethrow;
    }
  }

  Future<void> jumpingDepartureCompleted(
      PlateModel plate,
      PlateState plateState,
      ) async {
    final documentId = '${plate.plateNumber}_${plate.area}';

    try {
      await _repository.updatePlate(documentId, {
        'type': PlateType.departureCompleted.firestoreValue,
        'isSelected': false,
        'selectedBy': null,
        'endTime': DateTime.now(),
      });

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

      final logMap = log.toMap()..removeWhere((k, v) => v == null);

      await _uploader.uploadForPlateLogTypeJson(
        logMap,
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

      debugPrint("✅ 출차 완료 상태로 업데이트 완료: $documentId");
    } catch (e) {
      debugPrint('🚨 출차 완료 업데이트 실패: $e');
      rethrow;
    }
  }

  Future<void> goBackToParkingCompleted(
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
      await _repository.updatePlate(documentId, {
        'type': PlateType.parkingRequests.firestoreValue,
        'location': newLocation,
        'isSelected': false,
        'selectedBy': null,
      });

      final log = PlateLogModel(
        plateNumber: plateNumber,
        division: _areaState.currentDivision,
        area: area,
        from: fromType.name,
        to: PlateType.parkingRequests.name,
        action: '${fromType.label} → ${PlateType.parkingRequests.label}',
        performedBy: performedBy,
        timestamp: DateTime.now(),
      );

      final logMap = log.toMap()..removeWhere((k, v) => v == null);

      await _uploader.uploadForPlateLogTypeJson(
        logMap,
        plateNumber,
        _areaState.currentDivision,
        area,
      );

      debugPrint("✅ 상태 복원 완료: $documentId");
    } catch (e) {
      if (e is FirebaseException && e.code == 'not-found') {
        debugPrint("🚫 문서를 찾을 수 없음: $documentId");
      } else {
        debugPrint("🚨 복원 오류: $e");
      }
    }
  }

  // 🔹 4. Private 메서드

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
      final selectedBy = plateData['selectedBy'] ?? performedBy;

      final updateData = {
        'type': toType.firestoreValue,
        'location': location,
        'userName': selectedBy,
        'isSelected': false,
        'selectedBy': null,
        'updatedAt': Timestamp.now(),
        if (toType == PlateType.departureCompleted) 'end_time': DateTime.now(),
      };

      await _repository.updatePlate(documentId, updateData);
      debugPrint("✅ 문서 상태 이동 완료: ${fromType.name} → ${toType.name} ($plateNumber)");

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

      final logMap = log.toMap()..removeWhere((k, v) => v == null);

      await _uploader.uploadForPlateLogTypeJson(
        logMap,
        plateNumber,
        _areaState.currentDivision,
        area,
      );

      return true;
    } catch (e) {
      debugPrint('🚨 문서 상태 이동 오류: $e');
      return false;
    }
  }
}
