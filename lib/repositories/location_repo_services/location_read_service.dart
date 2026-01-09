import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // kDebugMode, debugPrint

import '../../models/location_model.dart';
// import '../../utils/usage_reporter.dart';

class LocationReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<LocationModel>> getLocationsOnce(String area) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;

    // 1) Firestore 쿼리
    try {
      snapshot = await _firestore.collection('locations').where('area', isEqualTo: area).get();
    } catch (e, st) {
      // ✅ DebugDatabaseLogger 로직 제거
      if (kDebugMode) {
        debugPrint('❌ locations.read 실패(area=$area): $e');
        debugPrint('stack: $st');
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

    // 2) 문서 파싱(실패 시 해당 문서만 스킵)
    for (final doc in snapshot.docs) {
      final data = doc.data();
      try {
        results.add(LocationModel.fromMap(doc.id, data));
      } catch (e, st) {
        // ✅ DebugDatabaseLogger 로직 제거
        if (kDebugMode) {
          debugPrint('⚠️ Location parse 실패(id=${doc.id}, area=$area): $e');
          debugPrint('stack: $st');
          debugPrint('rawKeys(<=30): ${data.keys.take(30).toList()}');
        }
        // 파싱 실패 문서는 무시하고 계속 진행
      }
    }

    return results;
  }
}
