import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import 'plate_state.dart';

class MovementPlate {
  final PlateRepository _repository;

  MovementPlate(this._repository);

  Future<bool> transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String area,
    required String newType,
  }) async {
    final documentId = '${plateNumber}_$area';
    try {
      final documentData = await _repository.getDocument(fromCollection, documentId);
      if (documentData != null) {
        await _repository.deleteDocument(fromCollection, documentId);
        await _repository.addOrUpdateDocument(toCollection, documentId, {
          ...documentData.toMap(),
          'type': newType,
          'isSelected': false,
          'selectedBy': null,
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('🚨 데이터 이동 오류: $e');
      return false;
    }
  }

  Future<PlateModel?> _findPlate(String collection, String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';
    try {
      final documentData = await _repository.getDocument(collection, documentId);
      if (documentData != null) {
        return documentData; // ✅ 그대로 반환
      }
      return null;
    } catch (e) {
      debugPrint("🚨 Error in _findPlate: $e");
      return null;
    }
  }

  Future<void> updatePlateStatus({
    required String plateNumber,
    required String area,
    required String fromCollection,
    required String toCollection,
    required String newType,
  }) async {
    await transferData(
      fromCollection: fromCollection,
      toCollection: toCollection,
      plateNumber: plateNumber,
      area: area,
      newType: newType,
    );
  }

  Future<void> setParkingCompleted(String plateNumber, String area, PlateState plateState) async {
    final selectedPlate = await _findPlate('parking_requests', plateNumber, area);
    if (selectedPlate != null) {
      await _repository.deleteDocument('parking_requests', '${plateNumber}_$area');
      await transferData(
        fromCollection: 'parking_requests',
        toCollection: 'parking_completed',
        plateNumber: plateNumber,
        area: selectedPlate.area,
        newType: '입차 완료',
      );

      plateState.syncWithAreaState();
    }
  }

  Future<void> setDepartureRequested(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'parking_completed',
      toCollection: 'departure_requests',
      newType: '출차 요청',
    );
  }

  Future<void> setDepartureCompleted(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      newType: '출차 완료',
    );
  }

  Future<void> goBackToParkingRequest({
    required String fromCollection, // ✅ 출처 컬렉션 추가 (parking_completed 또는 departure_requests)
    required String plateNumber,
    required String area,
    String? newLocation,
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      // 🔹 출처 컬렉션에서 번호판 문서 가져오기
      final documentData = await _repository.getDocument(fromCollection, documentId);
      if (documentData == null) {
        debugPrint("🚨 Plate not found in $fromCollection");
        return;
      }

      final updatedLocation = (newLocation == null || newLocation.trim().isEmpty) ? "미지정" : newLocation;

      // 🔥 기존 데이터 삭제
      await _repository.deleteDocument(fromCollection, documentId);

      // ✅ parking_requests로 이동 (공통 로직 적용)
      await _repository.addOrUpdateDocument('parking_requests', documentId, {
        ...documentData.toMap(),
        'location': updatedLocation,
        'type': '입차 요청',
        'isSelected': false,
        'selectedBy': null,
      });

      debugPrint("✅ 번호판이 parking_requests로 이동됨: $plateNumber ($updatedLocation)");
    } catch (e) {
      debugPrint("🚨 goBackToParkingRequest 실패: $e");
    }
  }
}
