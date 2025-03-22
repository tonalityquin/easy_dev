import 'package:flutter/material.dart';
import '../../repositories/plate/plate_repository.dart';
import 'plate_state.dart';

class MovementPlate {
  final PlateRepository _repository;

  MovementPlate(this._repository);

  /// 공통 Plate 데이터 이동 처리
  Future<bool> _transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String area,
    required String newType,
  }) async {
    final documentId = '${plateNumber}_$area';
    try {
      final document = await _repository.getDocument(fromCollection, documentId);
      if (document == null) {
        debugPrint("🚫 [$fromCollection] 문서를 찾을 수 없음: $documentId");
        return false;
      }

      // 원본 삭제
      await _repository.deleteDocument(fromCollection, documentId);

      // 대상 컬렉션에 저장 (선택 해제 상태로)
      await _repository.addOrUpdateDocument(toCollection, documentId, {
        ...document.toMap(),
        'type': newType,
        'isSelected': false,
        'selectedBy': null,
      });

      debugPrint("✅ 문서 이동 완료: $fromCollection → $toCollection ($plateNumber)");
      return true;
    } catch (e) {
      debugPrint('🚨 문서 이동 오류: $e');
      return false;
    }
  }

  /// 입차 요청 → 입차 완료
  Future<void> setParkingCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
  ) async {
    final success = await _transferData(
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '입차 완료',
    );

    if (success) await plateState.fetchPlateData();
  }

  /// 입차 완료 → 출차 요청
  Future<void> setDepartureRequested(
    String plateNumber,
    String area,
    PlateState plateState,
  ) async {
    final success = await _transferData(
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 요청',
    );

    if (success) await plateState.fetchPlateData();
  }

  /// 출차 요청 → 출차 완료
  Future<void> setDepartureCompleted(
    String plateNumber,
    String area,
    PlateState plateState,
  ) async {
    final success = await _transferData(
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      plateNumber: plateNumber,
      area: area,
      newType: '출차 완료',
    );

    if (success) await plateState.fetchPlateData();
  }

  /// 어떤 상태에서든 입차 요청 상태로 되돌리기
  Future<void> goBackToParkingRequest({
    required String fromCollection,
    required String plateNumber,
    required String area,
    required PlateState plateState,
    String newLocation = "미지정",
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
      await plateState.fetchPlateData();
    } catch (e) {
      debugPrint("🚨 goBackToParkingRequest 오류: $e");
    }
  }

  /// 범용 업데이트 지원 (선택적으로 사용 가능)
  Future<void> updatePlateStatus({
    required String plateNumber,
    required String area,
    required PlateState plateState,
    required String fromCollection,
    required String toCollection,
    required String newType,
  }) async {
    final success = await _transferData(
      fromCollection: fromCollection,
      toCollection: toCollection,
      plateNumber: plateNumber,
      area: area,
      newType: newType,
    );

    if (success) await plateState.fetchPlateData();
  }
}
