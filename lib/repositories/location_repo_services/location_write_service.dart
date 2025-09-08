import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';

class LocationWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addSingleLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    final data = location.toFirestoreMap();

    try {
      await docRef.set(data);
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      rethrow;
    }
  }
}
