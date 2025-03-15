import 'package:flutter/material.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../models/plate_model.dart';

class DeletePlate {
  final PlateRepository _repository;
  final Map<String, List<PlateModel>> _data;

  DeletePlate(this._repository, this._data);

  Future<void> deletePlate(String collection, String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';
    try {
      await _repository.deleteDocument(collection, documentId);
      _data[collection]?.removeWhere((plate) => plate.plateNumber == plateNumber);
      debugPrint("✅ 번호판 삭제 완료 ($collection): $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 ($collection): $e");
    }
  }

  Future<void> deletePlateFromParkingRequest(String plateNumber, String area) async {
    await deletePlate('parking_requests', plateNumber, area);
  }

  Future<void> deletePlateFromParkingCompleted(String plateNumber, String area) async {
    await deletePlate('parking_completed', plateNumber, area);
  }

  Future<void> deletePlateFromDepartureRequest(String plateNumber, String area) async {
    await deletePlate('departure_requests', plateNumber, area);
  }
}
