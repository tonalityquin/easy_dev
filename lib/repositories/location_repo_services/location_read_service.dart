import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // kDebugMode, debugPrint
import '../../models/location_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
// import '../../utils/usage_reporter.dart';

class LocationReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<LocationModel>> getLocationsOnce(String area) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;

    // 1) Firestore 쿼리 실패 로깅
    try {
      snapshot = await _firestore.collection('locations').where('area', isEqualTo: area).get();
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'locations.read',
          'collection': 'locations',
          'query': {'area': area},
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'read', 'error'],
        }, level: 'error');
      } catch (_) {
        /* 로깅 실패는 무시 */
      }
      rethrow;
    }

    // ✅ 읽기 비용 보고(문서수 기준, 0이면 1로 보정)
    /*final readN = snapshot.docs.isEmpty ? 1 : snapshot.docs.length;
    await UsageReporter.instance.report(
      area: area,
      action: 'read',
      n: readN,
      source: 'LocationReadService.getLocationsOnce',
    );*/

    final results = <LocationModel>[];

    // 2) 문서 파싱 실패 로깅
    for (final doc in snapshot.docs) {
      final data = doc.data();
      try {
        results.add(LocationModel.fromMap(doc.id, data));
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('⚠️ Location parse 실패(id=${doc.id}): $e');
        }
        // 동기 컨텍스트 → await 불가. 로깅 실패는 무시.
        // ignore: unawaited_futures
        DebugFirestoreLogger().log({
          'op': 'locations.parse',
          'docId': doc.id,
          'area': area,
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'parse', 'error'],
          // 과도한 데이터 로깅 방지
          'rawKeys': data.keys.take(30).toList(),
        }, level: 'error');
      }
    }

    return results;
  }
}
