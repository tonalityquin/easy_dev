import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import 'location_repository.dart';

class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔁 실시간 스트림 (필요 없으면 사용 안 해도 됨)
  @override
  Stream<List<LocationModel>> getLocationsStream(String area) {
    return _firestore
        .collection('locations')
        .where('area', isEqualTo: area)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => LocationModel.fromMap(doc.id, doc.data())).toList());
  }

  /// ✅ 단발성 조회 (.get() 기반)
  @override
  Future<List<LocationModel>> getLocationsOnce(String area) async {
    try {
      final snapshot = await _firestore
          .collection('locations')
          .where('area', isEqualTo: area)
          .get();

      return snapshot.docs
          .map((doc) => LocationModel.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// ➕ 단일 주차 구역 추가
  @override
  Future<void> addLocation(LocationModel location) async {
    final docRef = _firestore.collection('locations').doc(location.id);
    await docRef.set(location.toFirestoreMap());
  }

  /// ❌ 여러 주차 구역 삭제
  @override
  Future<void> deleteLocations(List<String> ids) async {
    final batch = _firestore.batch();
    for (final id in ids) {
      final docRef = _firestore.collection('locations').doc(id);
      batch.delete(docRef);
    }
    await batch.commit();
  }

  /// ✅ 선택 여부 토글
  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    final docRef = _firestore.collection('locations').doc(id);
    await docRef.update({'isSelected': isSelected});
  }

  /// ➕ 복합 주차 구역 추가 (상위 + 하위)
  @override
  Future<void> addCompositeLocation(String parent, List<String> subs, String area) async {
    final batch = _firestore.batch();

    // 상위 구역
    final parentRef = _firestore.collection('locations').doc(parent);
    batch.set(parentRef, {
      'locationName': parent,
      'area': area,
      'parent': area,
      'type': 'composite',
      'isSelected': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 하위 구역들
    for (final sub in subs) {
      final subRef = _firestore.collection('locations').doc(sub);
      batch.set(subRef, {
        'locationName': sub,
        'area': area,
        'parent': parent,
        'type': 'single',
        'isSelected': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}
