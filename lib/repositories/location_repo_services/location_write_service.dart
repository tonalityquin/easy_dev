import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart';

class LocationWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addSingleLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    final data = location.toFirestoreMap();

    try {
      await docRef.set(data);

      // ✅ write 1회 (정확한 테넌트로)
      final area = (data['area'] ?? location.area ?? 'unknown') as String;
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'LocationWriteService.addSingleLocation',
      );
    } catch (e, st) {
      // 실패 시 Firestore 로깅만 (error 레벨)
      try {
        await DebugFirestoreLogger().log({
          'op': 'locations.write.single',
          'docPath': docRef.path,
          'docId': location.id,
          'dataPreview': {
            'keys': data.keys.take(30).toList(),
            'len': data.length,
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': (e).code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'write', 'single', 'error'],
        }, level: 'error');
      } catch (_) {/* 로깅 실패는 무시 */}
      rethrow;
    }
  }

  Future<void> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs,
      String area,
      ) async {
    final batch = _firestore.batch();
    int writeOps = 0;

    for (final sub in subs) {
      final rawName = sub['name'] ?? '';
      final cleanName = rawName.toString().replaceAll('_$area', '');
      final cleanParent = parent.replaceAll('_$area', '');
      final subId = '${cleanName}_$area';

      final docRef = _firestore.collection('locations').doc(subId);

      batch.set(docRef, {
        'locationName': cleanName,
        'area': area,
        'parent': cleanParent,
        'type': 'composite',
        'isSelected': false,
        'capacity': sub['capacity'] ?? 0,
        'timestamp': FieldValue.serverTimestamp(),
      });
      writeOps += 1;
    }

    try {
      await batch.commit();

      // ✅ batch write 개수만큼 비용 보고
      if (writeOps > 0) {
        await UsageReporter.instance.report(
          area: area,
          action: 'write',
          n: writeOps,
          source: 'LocationWriteService.addCompositeLocation',
        );
      }
    } catch (e, st) {
      // 실패 시 Firestore 로깅만 (error 레벨)
      try {
        await DebugFirestoreLogger().log({
          'op': 'locations.write.composite',
          'collection': 'locations',
          'parent': parent,
          'area': area,
          'subs': {
            'len': subs.length,
            'sampleNames': subs
                .map((m) => (m['name'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .take(10)
                .toList(),
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': (e).code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'write', 'composite', 'error'],
        }, level: 'error');
      } catch (_) {/* 로깅 실패는 무시 */}
      rethrow;
    }
  }

  Future<void> deleteLocations(List<String> ids) async {
    if (ids.isEmpty) return;

    final batch = _firestore.batch();
    for (final id in ids) {
      final docRef = _firestore.collection('locations').doc(id);
      batch.delete(docRef);
    }

    try {
      await batch.commit();

      // ✅ id 규칙이 '<name>_<area>'라면 area별로 그룹핑해서 정확히 보고
      final areaBuckets = <String, int>{};
      for (final id in ids) {
        final area = _inferAreaFromId(id);
        areaBuckets.update(area, (v) => v + 1, ifAbsent: () => 1);
      }
      for (final entry in areaBuckets.entries) {
        await UsageReporter.instance.report(
          area: entry.key,
          action: 'delete',
          n: entry.value,
          source: 'LocationWriteService.deleteLocations',
        );
      }
    } catch (e, st) {
      // 실패 시 Firestore 로깅만 (error 레벨)
      try {
        await DebugFirestoreLogger().log({
          'op': 'locations.delete.batch',
          'collection': 'locations',
          'ids': {
            'len': ids.length,
            'sample': ids.take(20).toList(),
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': (e).code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'delete', 'batch', 'error'],
        }, level: 'error');
      } catch (_) {/* 로깅 실패는 무시 */}
      rethrow;
    }
  }

  /// ids 규칙이 'name_area' 형태일 때 area 추론. 규칙이 다르면 'unknown'.
  String _inferAreaFromId(String id) {
    final idx = id.lastIndexOf('_');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }
}
