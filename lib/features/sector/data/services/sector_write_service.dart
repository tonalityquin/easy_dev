import '../../../../app/diagnostics/firebase_activity_meter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/sector_model.dart';
import 'sector_read_service.dart';

class SectorWriteService {
  SectorWriteService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(SectorReadService.collectionName);

  Future<SectorModel> addSector({
    required String area,
    required String name,
  }) async {
    final normalizedArea = _requireArea(area);
    final sectorName = _requireName(name);
    final normalizedName = normalizeSectorName(sectorName);
    final documentId = buildSectorDocumentId(
      name: sectorName,
      area: normalizedArea,
    );

    try {
      await _ensureUniqueName(
        area: normalizedArea,
        normalizedName: normalizedName,
      );

      final reference = _collection.doc(documentId);
      final existing = await reference.get().trackFirestore('GET', 'features/sector/data/services/sector_write_service.dart', collection: 'sector', readPurpose: 'SECTOR_CREATE_TARGET_EXISTENCE_CHECK');
      if (existing.exists) {
        throw SectorDuplicateNameException(sectorName);
      }

      final now = DateTime.now();
      await reference.set(<String, dynamic>{
        'area': normalizedArea,
        'name': sectorName,
        'normalizedName': normalizedName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }).trackFirestore('SET', 'features/sector/data/services/sector_write_service.dart', collection: 'sector');

      debugPrint(
        '[SectorWriteService] 등록 완료: id=$documentId, area=$normalizedArea, name=$sectorName',
      );
      return SectorModel(
        id: documentId,
        area: normalizedArea,
        name: sectorName,
        normalizedName: normalizedName,
        createdAt: now,
        updatedAt: now,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorWriteService] 등록 실패: id=$documentId, area=$normalizedArea, name=$sectorName, error=$error',
      );
      debugPrint('[SectorWriteService] stackTrace=$stackTrace');
      rethrow;
    }
  }

  Future<SectorModel> updateSector({
    required String id,
    required String area,
    required String name,
  }) async {
    final normalizedId = id.trim();
    final normalizedArea = _requireArea(area);
    final sectorName = _requireName(name);
    final normalizedName = normalizeSectorName(sectorName);
    final targetId = buildSectorDocumentId(
      name: sectorName,
      area: normalizedArea,
    );
    if (normalizedId.isEmpty) {
      throw const SectorNotFoundException();
    }

    try {
      final sourceReference = _collection.doc(normalizedId);
      final sourceSnapshot = await sourceReference.get().trackFirestore('GET', 'features/sector/data/services/sector_write_service.dart', collection: 'sector', readPurpose: 'SECTOR_RENAME_SOURCE_VALIDATION');
      if (!sourceSnapshot.exists || sourceSnapshot.data() == null) {
        throw const SectorNotFoundException();
      }

      final sourceData = sourceSnapshot.data()!;
      final current = SectorModel.fromMap(normalizedId, sourceData);
      if (current.area != normalizedArea) {
        throw const SectorAreaMismatchException();
      }

      await _ensureUniqueName(
        area: normalizedArea,
        normalizedName: normalizedName,
        excludedId: normalizedId,
      );

      final now = DateTime.now();
      if (targetId == normalizedId) {
        await sourceReference.update(<String, dynamic>{
          'name': sectorName,
          'normalizedName': normalizedName,
          'updatedAt': FieldValue.serverTimestamp(),
        }).trackFirestore('UPDATE', 'features/sector/data/services/sector_write_service.dart', collection: 'sector');
      } else {
        final targetReference = _collection.doc(targetId);
        final targetSnapshot = await targetReference.get().trackFirestore('GET', 'features/sector/data/services/sector_write_service.dart', collection: 'sector', readPurpose: 'SECTOR_RENAME_TARGET_DUPLICATE_CHECK');
        if (targetSnapshot.exists) {
          throw SectorDuplicateNameException(sectorName);
        }

        final batch = _firestore.trackedActivityBatch('features/sector/data/services/sector_write_service.dart');
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/sector/data/services/sector_write_service.dart', result: 'staged');
        batch.set(targetReference, <String, dynamic>{
          'area': normalizedArea,
          'name': sectorName,
          'normalizedName': normalizedName,
          'createdAt': sourceData['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_DELETE', source: 'features/sector/data/services/sector_write_service.dart', result: 'staged');
        batch.delete(sourceReference);
        await batch.commit().trackFirestore('BATCH', 'features/sector/data/services/sector_write_service.dart', collection: 'sector');
      }

      debugPrint(
        '[SectorWriteService] 수정 완료: sourceId=$normalizedId, targetId=$targetId, area=$normalizedArea, name=$sectorName',
      );
      return current.copyWith(
        id: targetId,
        name: sectorName,
        normalizedName: normalizedName,
        updatedAt: now,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorWriteService] 수정 실패: sourceId=$normalizedId, targetId=$targetId, area=$normalizedArea, name=$sectorName, error=$error',
      );
      debugPrint('[SectorWriteService] stackTrace=$stackTrace');
      rethrow;
    }
  }

  Future<void> _ensureUniqueName({
    required String area,
    required String normalizedName,
    String? excludedId,
  }) async {
    final snapshot = await _collection.where('area', isEqualTo: area).get().trackFirestore('QUERY', 'features/sector/data/services/sector_write_service.dart', collection: 'sector');
    for (final document in snapshot.docs) {
      if (document.id == excludedId) continue;
      final data = document.data();
      final storedName = (data['name'] ?? '').toString().trim();
      final storedNormalized =
          (data['normalizedName'] ?? '').toString().trim();
      final comparable = normalizeSectorName(
        storedNormalized.isEmpty ? storedName : storedNormalized,
      );
      if (comparable == normalizedName) {
        throw SectorDuplicateNameException(storedName);
      }
    }
  }

  String _requireArea(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    if (normalized.contains('/')) {
      throw StateError('현재 지역명으로 섹터 문서명을 생성할 수 없습니다.');
    }
    return normalized;
  }

  String _requireName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('섹터명을 입력해야 합니다.');
    }
    if (normalized.contains('/')) {
      throw ArgumentError('섹터명에는 / 문자를 사용할 수 없습니다.');
    }
    return normalized;
  }
}
