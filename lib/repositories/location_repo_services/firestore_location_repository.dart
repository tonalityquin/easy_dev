import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/location_model.dart';
import 'location_repository.dart';
import 'location_read_service.dart';
import 'location_write_service.dart';
import 'location_count_service.dart';

class FirestoreLocationRepository implements LocationRepository {
  final LocationReadService _readService = LocationReadService();
  final LocationWriteService _writeService = LocationWriteService();
  final LocationCountService _countService = LocationCountService();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<LocationModel>> getLocationsOnce(String area) {
    return _readService.getLocationsOnce(area);
  }

  @override
  Future<void> addSingleLocation(LocationModel location) {
    return _writeService.addSingleLocation(location);
  }

  @override
  Future<void> deleteLocations(List<String> ids) {
    return _writeService.deleteLocations(ids);
  }

  @override
  Future<void> addCompositeLocation(
    String parent,
    List<Map<String, dynamic>> subs,
    String area,
  ) {
    return _writeService.addCompositeLocation(parent, subs, area);
  }

  // 집계 캐시 문서 1회 읽기
  Future<Map<String, int>> _getCachedCounts({
    required String area,
    required String type,
  }) async {
    final doc = await _firestore.collection('areas').doc(area).collection('locationCounts').doc(type).get();

    if (!doc.exists) return {};
    final data = doc.data();
    if (data == null) return {};

    final raw = Map<String, dynamic>.from(data['counts'] ?? {});
    return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  @override
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  }) async {
    final requested = locationNames.toSet().toList(); // 중복 제거

    try {
      final cached = await _getCachedCounts(area: area, type: type);
      if (cached.isNotEmpty) {
        final result = <String, int>{};
        final missing = <String>[];

        for (final name in requested) {
          final hit = cached[name];
          if (hit != null) {
            result[name] = hit;
          } else {
            missing.add(name);
          }
        }

        final hitCount = result.length;
        final missCount = missing.length;
        debugPrint(
            '🟩 Repository 캐시 조회: 요청 ${requested.length}개 / 히트 $hitCount / 미스 $missCount (area=$area, type=$type)');

        if (missing.isEmpty) return result;

        final rest = await _countService.getPlateCountsForLocations(
          locationNames: missing,
          area: area,
          type: type,
        );
        debugPrint('🟨 Repository 미스 보충: ${rest.length}개 count() 수행');

        result.addAll(rest);
        return result;
      }
    } catch (e) {
      debugPrint('🟥 Repository 캐시 조회 실패 → 폴백: $e');
    }

    debugPrint('🟥 Repository 캐시 없음 → 전체 ${requested.length}개 count() 수행');
    return _countService.getPlateCountsForLocations(
      locationNames: requested,
      area: area,
      type: type,
    );
  }
}
