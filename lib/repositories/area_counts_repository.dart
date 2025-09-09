// File: lib/repositories/area_counts_repository.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../enums/plate_type.dart';
import '../screens/dev_package/debug_package/debug_firestore_logger.dart';

class AreaCount {
  final String area;
  final Map<PlateType, int> counts;
  const AreaCount(this.area, this.counts);
}

class AreaCountsRepository {
  AreaCountsRepository({
    FirebaseFirestore? firestore,
    this.countTimeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration countTimeout;

  /// division 기준으로 area 목록을 가져오고, 각 area 별 PlateType 카운트를 병렬로 수집
  Future<List<AreaCount>> fetchAreaCountsByDivision(String division) async {
    try {
      // areas 조회
      final areaSnapshot = await _firestore
          .collection('areas')
          .where('division', isEqualTo: division)
          .get();

      final areas = areaSnapshot.docs
          .map((doc) => (doc['name'] as String))
          .where((name) => name != division) // 기존 코드 호환: division 동일명 제외
          .toList();

      // 각 area의 타입별 카운트를 병렬 수집
      final areaFutures = areas.map((area) async {
        final counts = await _fetchCountsForArea(area);
        return AreaCount(area, counts);
      }).toList();

      final results = await Future.wait(areaFutures);
      results.sort((a, b) => a.area.compareTo(b.area));
      return results;

    } on FirebaseException catch (e, st) {
      // 🔴 파이어스토어 실패만 로깅
      try {
        await DebugFirestoreLogger().log({
          'op': 'areas.fetchAreaCountsByDivision',
          'collection': 'areas',
          'filters': {'division': division},
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['areas', 'counts', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<Map<PlateType, int>> _fetchCountsForArea(String area) async {
    try {
      final futures = PlateType.values.map((type) async {
        final agg = await _firestore
            .collection('plates')
            .where('area', isEqualTo: area)
            .where('type', isEqualTo: type.firestoreValue)
            .count()
            .get()
            .timeout(countTimeout);

        final count = agg.count ?? 0;
        return MapEntry(type, count);
      }).toList();

      final entries = await Future.wait(futures);
      return Map<PlateType, int>.fromEntries(entries);

    } on FirebaseException catch (e, st) {
      // 🔴 파이어스토어 실패만 로깅
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.countByArea',
          'collection': 'plates',
          'filters': {'area': area, 'type': 'each(PlateType)'},
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
