import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/sector_model.dart';
import 'sector_read_service.dart';

class SectorDeleteService {
  SectorDeleteService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> deleteSector({
    required String id,
    required String area,
  }) async {
    final normalizedId = id.trim();
    final normalizedArea = area.trim();
    if (normalizedId.isEmpty) {
      throw const SectorNotFoundException();
    }
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }

    final reference = _firestore
        .collection(SectorReadService.collectionName)
        .doc(normalizedId);

    try {
      final snapshot = await reference.get();
      if (!snapshot.exists || snapshot.data() == null) {
        throw const SectorNotFoundException();
      }

      final sector = SectorModel.fromMap(normalizedId, snapshot.data()!);
      if (sector.area != normalizedArea) {
        throw const SectorAreaMismatchException();
      }

      await reference.delete();
      debugPrint(
        '[SectorDeleteService] 삭제 완료: id=$normalizedId, area=$normalizedArea',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorDeleteService] 삭제 실패: id=$normalizedId, area=$normalizedArea, error=$error',
      );
      debugPrint('[SectorDeleteService] stackTrace=$stackTrace');
      rethrow;
    }
  }
}
