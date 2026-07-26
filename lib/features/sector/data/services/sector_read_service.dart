import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/sector_model.dart';

class SectorReadService {
  SectorReadService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionName = 'sector';

  final FirebaseFirestore _firestore;

  Future<List<SectorModel>> getSectors(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }

    try {
      final snapshot = await _firestore
          .collection(collectionName)
          .where('area', isEqualTo: normalizedArea)
          .get();

      final sectors = <SectorModel>[];
      for (final document in snapshot.docs) {
        final sector = SectorModel.fromMap(document.id, document.data());
        if (sector.id.isEmpty || sector.name.isEmpty) {
          debugPrint(
            '[SectorReadService] 유효하지 않은 문서를 제외했습니다: ${document.id}',
          );
          continue;
        }
        if (sector.area != normalizedArea) continue;
        sectors.add(sector);
      }

      sectors.sort((a, b) {
        final normalizedCompare =
            a.normalizedName.compareTo(b.normalizedName);
        if (normalizedCompare != 0) return normalizedCompare;
        return a.name.compareTo(b.name);
      });

      debugPrint(
        '[SectorReadService] 조회 완료: area=$normalizedArea, count=${sectors.length}',
      );
      return sectors;
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorReadService] 조회 실패: area=$normalizedArea, error=$error',
      );
      debugPrint('[SectorReadService] stackTrace=$stackTrace');
      rethrow;
    }
  }
}
