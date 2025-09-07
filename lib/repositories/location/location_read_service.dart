import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import '../../screens/type_package/debugs/firestore_logger.dart';

class LocationReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<LocationModel>> getLocationsOnce(String area) async {
    await FirestoreLogger().log('getLocationsOnce called (area=$area)');

    try {
      final snapshot = await _firestore
          .collection('locations')
          .where('area', isEqualTo: area)
          .get();

      final result = snapshot.docs
          .map((doc) => LocationModel.fromMap(doc.id, doc.data()))
          .toList();

      await FirestoreLogger()
          .log('getLocationsOnce success: ${result.length} items loaded');

      return result;
    } catch (e) {
      await FirestoreLogger().log('getLocationsOnce error: $e');
      rethrow;
    }
  }
}
