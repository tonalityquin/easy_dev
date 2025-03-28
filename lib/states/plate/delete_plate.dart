import 'package:flutter/material.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';
import '../../models/plate_log_model.dart';
import 'log_plate.dart';

class DeletePlate {
  final PlateRepository _repository;
  final Map<String, List<PlateModel>> _data;
  final LogPlateState _logState; // ✅ 로그 상태 추가

  DeletePlate(this._repository, this._data, this._logState);

  Future<void> deletePlate(String collection, String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    final documentId = '${plateNumber}_$area';

    try {
      await _repository.deleteDocument(collection, documentId);
      _data[collection]?.removeWhere((plate) => plate.plateNumber == plateNumber);

      debugPrint("✅ 번호판 삭제 완료 ($collection): $plateNumber");

      // ✅ 로그 저장
      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: area,
          from: collection,
          to: '-',
          action: '삭제',
          performedBy: performedBy,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 ($collection): $e");
    }
  }

  Future<void> deletePlateFromParkingRequest(String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    await deletePlate('parking_requests', plateNumber, area, performedBy: performedBy);
  }

  Future<void> deletePlateFromParkingCompleted(String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    await deletePlate('parking_completed', plateNumber, area, performedBy: performedBy);
  }

  Future<void> deletePlateFromDepartureRequest(String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    await deletePlate('departure_requests', plateNumber, area, performedBy: performedBy);
  }
}
