import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';

class LocationReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<LocationModel>> getLocationsOnce(String area) async {
    try {
      final snapshot = await _firestore.collection('locations').where('area', isEqualTo: area).get();

      final result = snapshot.docs.map((doc) => LocationModel.fromMap(doc.id, doc.data())).toList();

      return result;
    } catch (e) {
      rethrow;
    }
  }
}
