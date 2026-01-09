// lib/repositories/plate_repo_services/plate_count_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
// import '../../utils/usage_reporter.dart';

class _CacheItem<T> {
  final T value;
  final DateTime at;

  _CacheItem(this.value, this.at);
}

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ 30초 TTL 메모리 캐시 (int 전용)
  static final Map<String, _CacheItem<int>> _cache = {};
  static const Duration _ttl = Duration(seconds: 30);

  // 🔧 int 전용으로 단순화
  int? _getCached(String key) {
    final v = _cache[key];
    if (v == null) return null;
    if (DateTime.now().difference(v.at) > _ttl) {
      _cache.remove(key);
      return null;
    }
    return v.value;
  }

  void _setCached(String key, int value) {
    _cache[key] = _CacheItem<int>(value, DateTime.now());
  }

  // ─────────────────────────────
  // ✅ 입차 전체 집계 (parking_completed, area 필터)
  // ─────────────────────────────
  Future<int> getParkingCompletedAggCount(String area) async {
    final cacheKey = 'park_all_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg = await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0;

      /*await UsageReporter.instance.reportSampled(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateCountService.getParkingCompletedCountAll',
        sampleRate: 0.2,
      );*/

      _setCached(cacheKey, count);
      return count;
    } catch (_) {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  // ─────────────────────────────
  // ✅ 출차 aggregation 전용
  //    - plates 컬렉션만 집계
  //    - type = departure_completed
  //    - isLockedFee = true
  // ─────────────────────────────
  Future<int> getDepartureCompletedAggCount(String area) async {
    final cacheKey = 'dep_agg_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg = await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int docCount = agg.count ?? 0;

      /*await UsageReporter.instance.reportSampled(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateCountService.getDepartureCompletedAggCount',
        sampleRate: 0.2,
      );*/

      _setCached(cacheKey, docCount);
      return docCount;
    } catch (_) {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  // ─────────────────────────────
  // ✅ 출차 보정치 전용
  //    - plate_counters/area_<area>.departureCompletedEvents
  // ─────────────────────────────
  Future<int> getDepartureCompletedExtraCount(String area) async {
    final cacheKey = 'dep_extra_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    try {
      final extraSnap = await _firestore.collection('plate_counters').doc('area_$area').get();

      final int extras = (extraSnap.data()?['departureCompletedEvents'] as int?) ?? 0;

      /*await UsageReporter.instance.reportSampled(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateCountService.getDepartureCompletedExtraCount',
        sampleRate: 0.2,
      );*/

      _setCached(cacheKey, extras);
      return extras;
    } catch (_) {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }
}
