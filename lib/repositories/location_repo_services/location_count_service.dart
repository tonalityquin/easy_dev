import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';

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
      } catch (_) {}
      rethrow;
    }
  }

  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  }) async {
    try {
      final uniq = locationNames.toSet().toList(); // ✅ 중복 제거
      const window = 10; // ✅ 동시성 제한(버스트 완화)

      final result = <String, int>{};
      for (int i = 0; i < uniq.length; i += window) {
        final end = (i + window < uniq.length) ? i + window : uniq.length;
        final slice = uniq.sublist(i, end);

        final entries = await Future.wait(slice.map((name) async {
          final count = await getPlateCount(
            locationName: name,
            area: area,
            type: type,
          );
          return MapEntry(name, count);
        }));

        result.addEntries(entries);
        debugPrint('🚚 batch 진행: ${result.length}/${uniq.length} (이번 청크 ${slice.length})');
      }

      return result;
    } catch (e, st) {
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
      } catch (_) {}
      rethrow;
    }
  }
}
