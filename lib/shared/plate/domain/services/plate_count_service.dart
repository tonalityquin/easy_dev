import 'plate_document_paths.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import '../../../../app/utils/status_dialog.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/plate_type.dart';

class _CacheItem<T> {
  final T value;
  final DateTime at;

  _CacheItem(this.value, this.at);
}

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final Map<String, _CacheItem<int>> _cache = {};
  static const Duration _ttl = Duration(seconds: 30);

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

  Future<int> getParkingCompletedAggCount(String area, {String? companyId}) async {
    final scope = (companyId ?? '').trim();
    if (scope.isEmpty) throw StateError('PLATE_COUNT_COMPANY_SCOPE_REQUIRED');
    final cacheKey = 'park_all_${scope}_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    final baseQuery = _firestore
        .collection('plates')
        .where('companyId', isEqualTo: scope)
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg =
          await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => baseQuery.count().get(), source: 'plate_count_service.get').timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0;

      _setCached(cacheKey, count);
      StatusDialog.recordDebugOperation(
        'plate_counters',
        'parking_count_loaded',
        details: <String, Object?>{'count': count, 'companyKeyedCache': scope.isNotEmpty},
      );
      return count;
    } catch (_) {
      rethrow;
    }
  }

  Future<int> getDepartureCompletedAggCount(String area, {String? companyId}) async {
    final scope = (companyId ?? '').trim();
    if (scope.isEmpty) throw StateError('PLATE_COUNT_COMPANY_SCOPE_REQUIRED');
    final cacheKey = 'dep_agg_${scope}_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    final baseQuery = _firestore
        .collection('plates')
        .where('companyId', isEqualTo: scope)
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg =
          await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => baseQuery.count().get(), source: 'plate_count_service.get').timeout(const Duration(seconds: 10));
      final int docCount = agg.count ?? 0;

      _setCached(cacheKey, docCount);
      StatusDialog.recordDebugOperation(
        'plate_counters',
        'departure_count_loaded',
        details: <String, Object?>{'count': docCount, 'companyKeyedCache': scope.isNotEmpty},
      );
      return docCount;
    } catch (_) {
      rethrow;
    }
  }

  Future<int> getDepartureCompletedExtraCount(String area, {String? companyId}) async {
    final scope = (companyId ?? '').trim();
    if (scope.isEmpty) throw StateError('PLATE_COUNT_COMPANY_SCOPE_REQUIRED');
    final cacheKey = 'dep_extra_${scope}_$area';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached;

    try {
      final extraSnap =
          await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('plate_counters').doc(
            PlateDocumentPaths.counterId(area, companyId: scope)).get(), source: 'plate_count_service.get');

      final int extras =
          (extraSnap.data()?['departureCompletedEvents'] as int?) ?? 0;

      final documentCompany = (extraSnap.data()?['companyId'] ?? '').toString().trim();
      if (extraSnap.exists && documentCompany != scope) {
        StatusDialog.recordDebugOperation(
          'plate_counters', 'legacy_counter_scope_mismatch',
          details: <String, Object?>{'hasCompany': documentCompany.isNotEmpty},
        );
        throw StateError('PLATE_COUNTER_COMPANY_MISMATCH');
      }
      _setCached(cacheKey, extras);
      StatusDialog.recordDebugOperation(
        'plate_counters',
        'departure_extra_loaded',
        details: <String, Object?>{'count': extras, 'companyKeyedCache': scope.isNotEmpty},
      );
      return extras;
    } catch (_) {
      rethrow;
    }
  }
}
