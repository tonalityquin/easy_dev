import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import 'location_repository.dart';

class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔁 기존 실시간 스트림 방식
  @override
  Stream<List<LocationModel>> getLocationsStream(String area) {
    return _firestore
        .collection('locations')
        .where('area', isEqualTo: area)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => LocationModel.fromMap(doc.id, doc.data())).toList());
  }

  /// ✅ 새로 추가된 단발성 조회 방식 (.get())
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
      print('🔥 위치 단발성 조회 실패: $e');
      rethrow;
    }
  }

  @override
  Future<void> addLocation(LocationModel location) async {
    final docId = '${location.id}_${location.area}';
    final docRef = _firestore.collection('locations').doc(docId);
    await docRef.set(location.toMap());
  }

  /// ✅ 여러 위치 삭제
  @override
  Future<void> deleteLocations(List<String> ids) async {
    for (String id in ids) {
      await _firestore.collection('locations').doc(id).delete();
    }
  }

  /// ✅ 선택 상태 토글
  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    await _firestore.collection('locations').doc(id).update({'isSelected': isSelected});
  }

  /// ✅ 복합 위치 추가
  @override
  Future<void> addCompositeLocation(String parent, List<String> subs, String area) async {
    final now = FieldValue.serverTimestamp();

    for (final sub in subs) {
      final id = '$parent-$sub\_$area';
      await _firestore.collection('locations').doc(id).set({
        'id': id,
        'locationName': sub,
        'parent': parent,
        'area': area,
        'type': 'composite',
        'isSelected': false,
        'timestamp': now,
      });
    }
  }
}
