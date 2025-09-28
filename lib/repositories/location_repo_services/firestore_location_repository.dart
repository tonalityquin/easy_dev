import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/location_model.dart';
import 'location_repository.dart';
import 'location_read_service.dart';
import 'location_write_service.dart';
import 'location_count_service.dart';
// ✅ UsageReporter: 파이어베이스(읽기/쓰기/삭제) 발생 지점만 계측
import '../../utils/usage_reporter.dart';

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

  // 집계 캐시 문서 1회 읽기 (+ UsageReporter: READ 계측)
  Future<Map<String, int>> _getCachedCounts({
    required String area,
    required String type,
  }) async {
    final docRef = _firestore
        .collection('areas')
        .doc(area)
        .collection('locationCounts')
        .doc(type);

    try {
      final doc = await docRef.get();

      // ✅ 계측: READ (성공 시)
      try {
        final data = doc.data();
        final raw = (data == null)
            ? const <String, dynamic>{}
            : (Map<String, dynamic>.from(data['counts'] ?? {}));
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: raw.length, // 읽어온 카운트 키 개수
          source:
          'FirestoreLocationRepository._getCachedCounts.areas/$area/locationCounts/$type.get',
        );
      } catch (_) {
        // 계측 실패는 무시
      }

      if (!doc.exists) return {};
      final data = doc.data();
      if (data == null) return {};

      final raw = Map<String, dynamic>.from(data['counts'] ?? {});
      return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (e) {
      // ✅ 계측: READ (오류 시도)
      try {
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: 0,
          source:
          'FirestoreLocationRepository._getCachedCounts.areas/$area/locationCounts/$type.get.error',
        );
      } catch (_) {}
      return {};
    }
  }

  @override
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
    bool bypassCache = false, // ⬅⬅⬅ 추가
  }) async {
    final requested = locationNames.toSet().toList(); // 중복 제거

    // 🔵 캐시 무시 모드: 바로 count()
    if (bypassCache) {
      debugPrint(
          '⚡ bypassCache=true → Firestore count() 강제 수행: ${requested.length}개 (area=$area, type=$type)');
      return _countService.getPlateCountsForLocations(
        locationNames: requested,
        area: area,
        type: type,
      );
    }

    // ✅ 기존 캐시 → 미스만 count() 보충
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

    debugPrint(
        '🟥 Repository 캐시 없음 → 전체 ${requested.length}개 count() 수행 (area=$area, type=$type)');
    return _countService.getPlateCountsForLocations(
      locationNames: requested,
      area: area,
      type: type,
    );
  }
}
