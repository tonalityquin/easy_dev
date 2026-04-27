import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
      }
    }

    return results;
  }
}
