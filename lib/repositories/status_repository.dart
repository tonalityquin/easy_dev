import 'package:cloud_firestore/cloud_firestore.dart';

class StatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  /// Firestore 컬렉션 참조 반환 (중복 코드 제거)
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(collectionName);
  }

  /// Firestore 상태 데이터 실시간 스트림 반환 (지역 필터 적용)
  Stream<List<Map<String, dynamic>>> getStatusStream(String area) {
    return _getCollectionRef().where('area', isEqualTo: area).snapshots().map((snapshot) {
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

  /// Firestore에 상태 항목 추가
  Future<void> addToggleItem(Map<String, dynamic> item) async {
    try {
      await _getCollectionRef().doc(item['id']).set(item);
    } catch (e) {
      throw Exception("Firestore 저장 실패: ${e.toString()}");
    }
  }

  /// Firestore에서 상태 변경
  Future<void> updateToggleStatus(String id, bool isActive) async {
    try {
      await _getCollectionRef().doc(id).update({"isActive": isActive});
    } catch (e) {
      throw Exception("Firestore 업데이트 실패: ${e.toString()}");
    }
  }

  /// Firestore에서 상태 삭제
  Future<void> deleteToggleItem(String id) async {
    try {
      await _getCollectionRef().doc(id).delete();
    } catch (e) {
      throw Exception("Firestore 삭제 실패: ${e.toString()}");
    }
  }
}
