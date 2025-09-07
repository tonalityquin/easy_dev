import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import '../../screens/type_package/debugs/firestore_logger.dart';

class LocationWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addSingleLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    final data = location.toFirestoreMap();

    await FirestoreLogger().log('addSingleLocation called (id=${location.id}, data=$data)');

    try {
      await docRef.set(data);
      await FirestoreLogger().log('addSingleLocation success: ${location.id}');
    } catch (e) {
      await FirestoreLogger().log('addSingleLocation error: $e');
      rethrow;
    }
  }

  Future<void> addCompositeLocation(
    String parent,
    List<Map<String, dynamic>> subs,
    String area,
  ) async {
    await FirestoreLogger().log('addCompositeLocation called (parent=$parent, subs=${subs.length}, area=$area)');

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
      await FirestoreLogger().log('addCompositeLocation success: ${subs.length} subs saved');
    } catch (e) {
      await FirestoreLogger().log('addCompositeLocation error: $e');
      rethrow;
    }
  }

  Future<void> deleteLocations(List<String> ids) async {
    if (ids.isEmpty) return;

    await FirestoreLogger().log('deleteLocations called (ids=${ids.join(",")})');

    final batch = _firestore.batch();

    for (final id in ids) {
      final docRef = _firestore.collection('locations').doc(id);
      batch.delete(docRef);
    }

    try {
      await batch.commit();
      await FirestoreLogger().log('deleteLocations success');
    } catch (e) {
      await FirestoreLogger().log('deleteLocations error: $e');
      rethrow;
    }
  }
}
