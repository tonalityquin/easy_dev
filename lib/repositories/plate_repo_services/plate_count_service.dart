// lib/repositories/plate_repo_services/plate_count_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart'; // ✅

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> getParkingCompletedCountAll(String area) async {
    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg =
      await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0;

      // ✅ Aggregation read = 1 (서비스 레이어에서만 계측)
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateCountService.getParkingCompletedCountAll',
      );

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

      // ✅ 총 2번의 read가 있었음: count() 1, counters 1
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 2,
        source: 'PlateCountService.getDepartureCompletedCountAll',
      );

      return docCount + extras;
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
