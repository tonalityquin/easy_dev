import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import 'location_repository.dart';

class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<LocationModel>> getLocationsStream() {
    return _firestore.collection('locations').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => LocationModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  @override
  Future<void> addLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    await docRef.set(location.toMap());
  }

  @override
  Future<void> deleteLocations(List<String> ids) async {
    for (String id in ids) {
      await _firestore.collection('locations').doc(id).delete();
    }
  }

  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    await _firestore.collection('locations').doc(id).update({'isSelected': isSelected});
  }
}
