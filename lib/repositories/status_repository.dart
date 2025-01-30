import 'package:cloud_firestore/cloud_firestore.dart';

class StatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  /// Firestore 상태 데이터 실시간 스트림 반환 (지역 필터 적용)
  Stream<List<Map<String, dynamic>>> getStatusStream(String area) {
    return _firestore
        .collection(collectionName)
        .where('area', isEqualTo: area) // 🔄 현재 선택된 지역에 해당하는 데이터만 가져오기
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'isActive': data['isActive'] ?? false,
          'area': data['area'] ?? '',
        };
      }).toList();
    });
  }

  /// Firestore에 상태 항목 추가 (지역 정보 포함)
  Future<void> addToggleItem(Map<String, dynamic> item) async {
    await _firestore.collection(collectionName).doc(item['id']).set(item);
  }

  /// Firestore에서 상태 변경
  Future<void> updateToggleStatus(String id, bool isActive) async {
    await _firestore.collection(collectionName).doc(id).update({"isActive": isActive});
  }

  /// Firestore에서 상태 삭제
  Future<void> deleteToggleItem(String id) async {
    await _firestore.collection(collectionName).doc(id).delete();
  }
}
