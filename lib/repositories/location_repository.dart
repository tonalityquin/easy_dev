import 'package:cloud_firestore/cloud_firestore.dart';

abstract class LocationRepository {
  Stream<List<Map<String, dynamic>>> getLocationsStream();
  Future<void> addLocation(String locationName, String area);
  Future<void> deleteLocations(List<String> ids);
  Future<void> toggleLocationSelection(String id, bool isSelected);
}

class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Map<String, dynamic>>> getLocationsStream() {
    return _firestore.collection('locations').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'locationName': data['locationName']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'isSelected': (data['isSelected'] ?? false) == true,
        };
      }).toList();
    });
  }

  @override
  Future<void> addLocation(String locationName, String area) async {
    try {
      await _firestore.collection('locations').doc(locationName).set({
        'locationName': locationName,
        'area': area,
        'isSelected': false,
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> deleteLocations(List<String> ids) async {
    try {
      for (var id in ids) {
        await _firestore.collection('locations').doc(id).delete();
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    try {
      await _firestore.collection('locations').doc(id).update({
        'isSelected': isSelected,
      });
    } catch (e) {
      rethrow;
    }
  }
}
