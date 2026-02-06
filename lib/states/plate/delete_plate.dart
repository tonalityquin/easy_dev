import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../repositories/plate_repo_services/plate_repository.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

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
    // ⚠️ “요금” 자체가 아니라, Firestore 과금 단위인 문서 Read/Write/Delete의 “예상” 횟수를 출력합니다.
    // deletePlate(documentId, area: area, syncViews: true) 기준:
    // - plates/{id} delete: 1 DELETE(=write로 과금)
    // - view 3종 items.{id} FieldValue.delete set(merge): 최대 3 WRITE (토글/정합성 게이트에 따라 실제 0~3)
    final estimatedDeletes = 1;
    final estimatedViewWritesMax = syncViews ? 3 : 0;
    final estimatedReads = 0; // area를 넘기므로 delete 경로에서 read가 “필수”는 아님(구현에 따라 달라질 수 있음)

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
      // ✅ 수정안 반영: area 전달 + view 정리(syncViews) 옵션 전달
      await _repository.deletePlate(
        documentId,
        area: area,
        syncViews: syncViews,
      );

      // ✅ 수정: plateNumber만으로 제거하면 다른 area의 동일 plate까지 제거될 수 있어 area까지 조건으로 제거
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
