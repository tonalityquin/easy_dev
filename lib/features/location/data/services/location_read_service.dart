import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';

import '../../domain/models/location_model.dart';

class LocationReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<LocationModel>> getLocationsOnce(String area) async {
    final cleanArea = area.trim();

    QuerySnapshot<Map<String, dynamic>> snapshot;

    try {
      snapshot = await _firestore
          .collection('locations')
          .where('area', isEqualTo: cleanArea)
          .get();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ locations.read 실패(area=$cleanArea): $e');
        debugPrint('stack: $st');
      }
      await DevFirebaseDebugDialog.show(
        operation: 'personal.locations.read',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'locations',
          'area': cleanArea,
          'query': 'where(area == $cleanArea)',
          'filters': 'area == $cleanArea',
          'orderBy': 'none',
          'queryShape': 'single-field-equality',
          'compositeIndex': 'not-required-for-this-shape-unless-console-error-requires-it',
        },
      );
      rethrow;
    }

    final results = <LocationModel>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      try {
        results.add(LocationModel.fromMap(doc.id, data));
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('⚠️ Location parse 실패(id=${doc.id}, area=$cleanArea): $e');
          debugPrint('stack: $st');
          debugPrint('rawKeys(<=30): ${data.keys.take(30).toList()}');
        }
        await DevFirebaseDebugDialog.show(
          operation: 'personal.locations.parse',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'locations',
            'docId': doc.id,
            'area': cleanArea,
            'rawKeys': data.keys.take(40).toList(growable: false),
          },
        );
      }
    }

    return results;
  }
}
