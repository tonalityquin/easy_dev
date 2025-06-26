import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import 'location_repository.dart';

class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<LocationModel>> getLocationsOnce(String area) async {
    try {
      final snapshot = await _firestore.collection('locations').where('area', isEqualTo: area).get();

      return snapshot.docs.map((doc) => LocationModel.fromMap(doc.id, doc.data())).toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> addLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    await docRef.set(location.toFirestoreMap());
  }

  @override
  Future<void> deleteLocations(List<String> ids) async {
    final batch = _firestore.batch();
    for (final id in ids) {
      final docRef = _firestore.collection('locations').doc(id);
      batch.delete(docRef);
    }
    await batch.commit();
  }

  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    final docRef = _firestore.collection('locations').doc(id);
    await docRef.update({'isSelected': isSelected});
  }

  /// 🔁 복합 주차 구역 저장 시 용량(capacity)도 포함
  @override
  Future<void> addCompositeLocation(
    String parent,
    List<Map<String, dynamic>> subs, // {name, capacity}
    String area,
  ) async {
    final batch = _firestore.batch();

    for (final sub in subs) {
      final rawName = sub['name'] ?? '';

      // 🔹 지역명이 포함되어 있다면 제거: 예) B-3_Beta → B-3
      final cleanName = rawName.replaceAll('_$area', '');
      final cleanParent = parent.replaceAll('_$area', '');

      final subId = '${cleanName}_$area';
      final subRef = _firestore.collection('locations').doc(subId);

      batch.set(subRef, {
        'locationName': cleanName, // ✅ 지역명 없이
        'area': area,
        'parent': cleanParent, // ✅ 지역명 없이
        'type': 'composite', // 또는 'single' 등 정책에 맞게 조정
        'isSelected': false,
        'capacity': sub['capacity'] ?? 0,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<int> getPlateCountByLocation({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  }) async {
    final snapshot = await _firestore
        .collection('plates')
        .where('location', isEqualTo: locationName)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: type)
        .count()
        .get();

    return snapshot.count ?? 0;
  }
}
