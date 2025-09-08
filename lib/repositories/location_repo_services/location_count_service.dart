import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/community_package/debug_package/debug_firestore_logger.dart';

class LocationCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  }) async {
    try {
      final snapshot = await _firestore
          .collection('plates')
          .where('location', isEqualTo: locationName)
          .where('area', isEqualTo: area)
          .where('type', isEqualTo: type)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e, st) {
      // 실패 시 Firestore 로거에만 error 기록
      try {
        final payload = {
          'op': 'plates.count',
          'collection': 'plates',
          'filters': {
            'location': locationName,
            'area': area,
            'type': type,
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'error'],
        };
        await DebugFirestoreLogger().log(payload, level: 'error');
      } catch (_) {
        // 로깅 실패는 무시
      }
      rethrow;
    }
  }

  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  }) async {
    try {
      final futures = locationNames.map((name) async {
        final count = await getPlateCount(
          locationName: name,
          area: area,
          type: type,
        );
        return MapEntry(name, count);
      }).toList();

      final entries = await Future.wait(futures);
      final result = Map.fromEntries(entries);

      return result;
    } catch (e, st) {
      // 배치 조회 전체 실패 로깅 (개별 getPlateCount 내부에서도 실패 시 로깅함)
      try {
        final payload = {
          'op': 'plates.count.batch',
          'collection': 'plates',
          'filters': {
            'area': area,
            'type': type,
          },
          'locations': {
            'len': locationNames.length,
            'sample': locationNames.take(10).toList(),
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'batch', 'error'],
        };
        await DebugFirestoreLogger().log(payload, level: 'error');
      } catch (_) {
        // 로깅 실패는 무시
      }
      rethrow;
    }
  }
}
