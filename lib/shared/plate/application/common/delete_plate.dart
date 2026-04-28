import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_model.dart';
import '../../domain/repositories/plate_repository.dart';

class DeletePlate {
  final PlateRepository _repository;
  final Map<PlateType, List<PlateModel>> _data;

  DeletePlate(this._repository, this._data);

  String _docId(String plateNumber, String area) => '${plateNumber}_$area';

  void _debugDeleteCost({
    required PlateType type,
    required String plateNumber,
    required String area,
    required bool syncViews,
  }) {
    
    
    
    
    final estimatedDeletes = 1;
    final estimatedViewWritesMax = syncViews ? 3 : 0;
    final estimatedReads = 0; 

    debugPrint(
      '🧾 [DeletePlate] delete 요청 (${type.firestoreValue}) plate=$plateNumber area=$area '
          'syncViews=$syncViews | 예상 ops: READ~$estimatedReads, DELETE~$estimatedDeletes, VIEW_WRITES~0..$estimatedViewWritesMax',
    );
  }

  Future<void> deletePlate(
      PlateType type,
      String plateNumber,
      String area, {
        String performedBy = 'Unknown',
        bool syncViews = true,
      }) async {
    final documentId = _docId(plateNumber, area);

    _debugDeleteCost(
      type: type,
      plateNumber: plateNumber,
      area: area,
      syncViews: syncViews,
    );

    try {
      
      await _repository.deletePlate(
        documentId,
        area: area,
        syncViews: syncViews,
      );

      
      _data[type]?.removeWhere(
            (plate) => plate.plateNumber == plateNumber && plate.area == area,
      );

      debugPrint(
        "✅ 번호판 삭제 완료 (${type.firestoreValue}): $plateNumber / $area (by $performedBy, syncViews=$syncViews)",
      );
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 (${type.firestoreValue}): $e");
      rethrow;
    }
  }

  Future<void> deleteFromParkingRequest(
      String plateNumber,
      String area, {
        String performedBy = 'Unknown',
        bool syncViews = true,
      }) async {
    await deletePlate(
      PlateType.parkingRequests,
      plateNumber,
      area,
      performedBy: performedBy,
      syncViews: syncViews,
    );
  }

  Future<void> deleteFromDepartureRequest(
      String plateNumber,
      String area, {
        String performedBy = 'Unknown',
        bool syncViews = true,
      }) async {
    await deletePlate(
      PlateType.departureRequests,
      plateNumber,
      area,
      performedBy: performedBy,
      syncViews: syncViews,
    );
  }

  Future<void> deleteFromParkingCompleted(
      String plateNumber,
      String area, {
        String performedBy = 'Unknown',
        bool syncViews = true,
      }) async {
    await deletePlate(
      PlateType.parkingCompleted,
      plateNumber,
      area,
      performedBy: performedBy,
      syncViews: syncViews,
    );
  }
}
