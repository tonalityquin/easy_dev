import 'package:cloud_firestore/cloud_firestore.dart';

class LocationCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  }) async {
    try {
      final snapshot = await _firestore
          .collection('plates')
          .where('location', isEqualTo: locationName)
          .where('area', isEqualTo: area)
          .where('type', isEqualTo: type)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  }) async {
    try {
      final futures = locationNames.map((name) async {
        final count = await getPlateCount(
          locationName: name,
          area: area,
          type: type,
        );
        return MapEntry(name, count);
      }).toList();

      final entries = await Future.wait(futures);
      final result = Map.fromEntries(entries);

      return result;
    } catch (e) {
      rethrow;
    }
  }
}
