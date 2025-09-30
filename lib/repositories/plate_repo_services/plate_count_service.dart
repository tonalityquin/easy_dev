// lib/repositories/plate_repo_services/plate_count_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart'; // ✅

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

  Future<int> getParkingCompletedCountAll(String area) async {
    final cacheKey = 'park_all_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg =
      await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0;

      // ✅ Aggregation read = 1 (서비스 레이어에서만 계측) — 샘플링
      await UsageReporter.instance.reportSampled(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateCountService.getParkingCompletedCountAll',
        sampleRate: 0.2,
      );

      _setCached(cacheKey, count);
      return count;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.count.parkingCompletedAll',
          'collection': 'plates',
          'filters': {
            'type': PlateType.parkingCompleted.firestoreValue,
            'area': area,
          },
          'meta': {'timeoutSec': 10},
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'parkingCompletedAll', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<int> getDepartureCompletedCountAll(String area) async {
    final cacheKey = 'dep_all_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg =
      await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int docCount = agg.count ?? 0;

      // 🔹 보정치(재생성 이벤트 카운터) 1회 읽기 → 총 2회 READ
      final extraSnap =
      await _firestore.collection('plate_counters').doc('area_$area').get();
      final int extras =
          (extraSnap.data()?['departureCompletedEvents'] as int?) ?? 0;

      // ✅ 총 2번의 read: count() 1, counters 1 — 샘플링
      await UsageReporter.instance.reportSampled(
        area: area,
        action: 'read',
        n: 2,
        source: 'PlateCountService.getDepartureCompletedCountAll',
        sampleRate: 0.2,
      );

      final v = docCount + extras;
      _setCached(cacheKey, v);
      return v;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.count.departureCompletedAll',
          'collection': 'plates',
          'filters': {
            'type': PlateType.departureCompleted.firestoreValue,
            'area': area,
            'isLockedFee': true,
          },
          'meta': {'timeoutSec': 10},
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'departureCompletedAll', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
