import 'package:cloud_firestore/cloud_firestore.dart';
















enum LocationQueryField {
  full, 
  leaf, 
}

class LocationCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _sep = ' - ';

  
  
  
  String _normalizeFull(String displayName) {
    final v = displayName.trim();
    return v.isEmpty ? '미지정' : v;
  }

  
  
  String _extractLeaf(String displayName) {
    final full = _normalizeFull(displayName);
    if (!full.contains(_sep)) return full;
    final parts = full.split(_sep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return full;
    return parts.last;
  }

  
  
  
  
  
  
  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
    LocationQueryField locationField = LocationQueryField.full,
  }) async {
    final _area = area.trim();
    final _type = type.trim();

    
    final full = _normalizeFull(locationName);
    final leaf = _extractLeaf(locationName);

    
    final String fieldPath;
    final String value;
    switch (locationField) {
      case LocationQueryField.full:
        fieldPath = 'location.full';
        value = full;
        break;
      case LocationQueryField.leaf:
        fieldPath = 'location.leaf';
        value = leaf;
        break;
    }

    try {
      final snapshot = await _firestore
          .collection('plates')
          .where(fieldPath, isEqualTo: value)
          .where('area', isEqualTo: _area)
          .where('type', isEqualTo: _type)
          .count()
          .get();

      final int safeCount = snapshot.count ?? 0;
      return safeCount;
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  
  
  
  
  
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames, 
    required String area,
    String type = 'parking_completed',
    LocationQueryField locationField = LocationQueryField.full,
  }) async {
    if (locationNames.isEmpty) return <String, int>{};

    final _area = area.trim();
    final _type = type.trim();

    try {
      final uniq = locationNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      const window = 10; 

      final result = <String, int>{};

      for (int i = 0; i < uniq.length; i += window) {
        final end = (i + window < uniq.length) ? i + window : uniq.length;
        final slice = uniq.sublist(i, end);

        final entries = await Future.wait(slice.map((displayName) async {
          final count = await getPlateCount(
            locationName: displayName, 
            area: _area,
            type: _type,
            locationField: locationField, 
          );
          return MapEntry(displayName, count);
        }));

        for (final e in entries) {
          result[e.key] = e.value;
        }
      }

      return result;
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }
}
