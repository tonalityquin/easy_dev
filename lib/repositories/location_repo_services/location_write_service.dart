import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';

class LocationWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addSingleLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    final data = location.toFirestoreMap();

    try {
      await docRef.set(data);
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
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'write', 'single', 'error'],
        }, level: 'error');
      } catch (_) {
        /* 로깅 실패는 무시 */
      }
      rethrow;
    }
  }

  Future<void> addCompositeLocation(
    String parent,
    List<Map<String, dynamic>> subs,
    String area,
  ) async {
    final batch = _firestore.batch();

    for (final sub in subs) {
      final rawName = sub['name'] ?? '';
      final cleanName = rawName.replaceAll('_$area', '');
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
    }

    try {
      await batch.commit();
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
            'sampleNames': subs.map((m) => (m['name'] ?? '').toString()).where((s) => s.isNotEmpty).take(10).toList(),
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'write', 'composite', 'error'],
        }, level: 'error');
      } catch (_) {
        /* 로깅 실패는 무시 */
      }
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
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['locations', 'delete', 'batch', 'error'],
        }, level: 'error');
      } catch (_) {
        /* 로깅 실패는 무시 */
      }
      rethrow;
    }
  }
}
