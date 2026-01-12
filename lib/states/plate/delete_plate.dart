import 'package:flutter/material.dart';
import '../../repositories/plate_repo_services/plate_repository.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

class DeletePlate {
  final PlateRepository _repository;
  final Map<PlateType, List<PlateModel>> _data;

  DeletePlate(this._repository, this._data);

  Future<void> deletePlate(PlateType type, String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    final documentId = '${plateNumber}_$area';

    try {
      await _repository.deletePlate(documentId);
      _data[type]?.removeWhere((plate) => plate.plateNumber == plateNumber);

      debugPrint("✅ 번호판 삭제 완료 (${type.firestoreValue}): $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 (${type.firestoreValue}): $e");
    }
  }

  Future<void> deleteFromParkingRequest(String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    await deletePlate(PlateType.parkingRequests, plateNumber, area, performedBy: performedBy);
  }

  Future<void> deleteFromDepartureRequest(String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    await deletePlate(PlateType.departureRequests, plateNumber, area, performedBy: performedBy);
  }

  Future<void> deleteFromParkingCompleted(String plateNumber, String area, {String performedBy = 'Unknown'}) async {
    await deletePlate(PlateType.parkingCompleted, plateNumber, area, performedBy: performedBy);
  }
}
