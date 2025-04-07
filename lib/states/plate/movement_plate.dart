import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import 'plate_state.dart';
import '../../models/plate_log_model.dart';
import 'log_plate.dart';

class MovementPlate {
  final PlateRepository _repository;
  final LogPlateState _logState;

  MovementPlate(this._repository, this._logState);

  /// 공통 Plate 데이터 이동 처리 + 로그 기록
  Future<bool> _transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String area,
    required String newType,
    required String location,
    String performedBy = '시스템',
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      final document = await _repository.getDocument(fromCollection, documentId);
      if (document == null) {
        debugPrint("🚫 [$fromCollection] 문서를 찾을 수 없음: $documentId");
        return false;
      }

      // 🔍 실제 plate 데이터를 가져옴
      final plateData = document.toMap();

      // 👤 담당자 추출: selectedBy 또는 기본값
      final selectedBy = plateData['selectedBy'] ?? '시스템';

      // 🔄 from → to 컬렉션으로 이동
      await _repository.deleteDocument(fromCollection, documentId);

      await _repository.addOrUpdateDocument(toCollection, documentId, {
        ...plateData,
        'type': newType,
        'location': location,
        'userName': selectedBy, // ✅ 사용자 이름 갱신
        'isSelected': false,
        'selectedBy': null,
        if (newType == '출차 완료') 'end_time': DateTime.now(),
      });

      debugPrint("✅ 문서 이동 완료: $fromCollection → $toCollection ($plateNumber)");

      // 📝 로그 저장
      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: area,
          from: fromCollection,
          to: toCollection,
          action: newType,
          performedBy: selectedBy,
          // ✅ 로그에도 담당자 반영
          timestamp: DateTime.now(),
        ),
      );

      return true;
    } catch (e) {
      debugPrint('🚨 문서 이동 오류: $e');
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
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '입차 완료',
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
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 요청',
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
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 완료',
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
      await _repository.deleteDocument('departure_requests', documentId);

      await _repository.addOrUpdateDocument('departure_completed', documentId, {
        ...plate.toMap(),
        'type': '출차 완료',
        'location': plate.location,
        'userName': plate.userName,
        'isSelected': false,
        'selectedBy': null,
        'end_time': DateTime.now(),
      });

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plate.plateNumber,
          area: plate.area,
          from: 'departure_requests',
          to: 'departure_completed',
          action: '출차 완료',
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
      fromCollection: 'parking_completed',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 완료',
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
      await _repository.deleteDocument('parking_completed', documentId);

      await _repository.addOrUpdateDocument('departure_completed', documentId, {
        ...plate.toMap(),
        'type': '출차 완료',
        'location': plate.location,
        'userName': plate.userName,
        'isSelected': false,
        'selectedBy': null,
        'end_time': DateTime.now(),
      });

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plate.plateNumber,
          area: plate.area,
          from: 'parking_completed',
          to: 'departure_completed',
          action: '출차 완료',
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
    required String fromCollection,
    required String plateNumber,
    required String area,
    required PlateState plateState,
    String newLocation = "미지정",
    String performedBy = '시스템',
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      final document = await _repository.getDocument(fromCollection, documentId);
      if (document == null) {
        debugPrint("🚫 $fromCollection 에서 문서를 찾을 수 없음: $documentId");
        return;
      }

      await _repository.deleteDocument(fromCollection, documentId);
      await _repository.addOrUpdateDocument('parking_requests', documentId, {
        ...document.toMap(),
        'location': newLocation,
        'type': '입차 요청',
        'isSelected': false,
        'selectedBy': null,
      });

      debugPrint("🔄 $fromCollection → parking_requests 이동 완료: $plateNumber");

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: area,
          from: fromCollection,
          to: 'parking_requests',
          action: '입차 요청 복원',
          performedBy: performedBy,
          timestamp: DateTime.now(),
        ),
      );

      await plateState.fetchPlateData();
    } catch (e) {
      debugPrint("🚨 goBackToParkingRequest 오류: $e");
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
      fromCollection: 'departure_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '입차 완료',
      location: location,
      performedBy: performedBy,
    );

    if (success) {
      await plateState.fetchPlateData();
    } else {
      debugPrint("🚫 출차 요청 → 입차 완료 이동 실패");
    }
  }

  Future<void> updatePlateStatus({
    required String plateNumber,
    required String area,
    required PlateState plateState,
    required String fromCollection,
    required String toCollection,
    required String newType,
    required String location,
    String performedBy = '시스템',
  }) async {
    final success = await _transferData(
      fromCollection: fromCollection,
      toCollection: toCollection,
      plateNumber: plateNumber,
      area: area,
      newType: newType,
      location: location,
      performedBy: performedBy,
    );

    if (success) await plateState.fetchPlateData();
  }
}
