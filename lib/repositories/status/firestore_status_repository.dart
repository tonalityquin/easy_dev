import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/status_model.dart';
import 'status_repository.dart';

class FirestoreStatusRepository implements StatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  /// 🔗 컬렉션 참조 반환
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(collectionName);
  }

  /// 🔁 실시간 상태 스트림
  @override
  Stream<List<StatusModel>> getStatusStream(String area) {
    return _getCollectionRef()
        .where('area', isEqualTo: area)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => StatusModel.fromMap(doc.id, doc.data()))
        .toList());
  }

  /// ✅ 단발성 조회 (.get())
  @override
  Future<List<StatusModel>> getStatusesOnce(String area) async {
    try {
      final snapshot = await _getCollectionRef()
          .where('area', isEqualTo: area)
          .get();

      final result = snapshot.docs
          .map((doc) => StatusModel.fromMap(doc.id, doc.data()))
          .toList();

      debugPrint('✅ Firestore 상태 ${result.length}건 로딩 완료');
      return result;
    } catch (e) {
      debugPrint('🔥 Firestore 상태 단발성 조회 실패: $e');
      rethrow;
    }
  }

  /// ➕ 상태 항목 추가
  @override
  Future<void> addToggleItem(StatusModel status) async {
    final docRef = _getCollectionRef().doc(status.id); // ID 명시
    final data = status.toFirestoreMap(); // ✅ toMap → toFirestoreMap 변경

    // 빈 값 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint('✅ Firestore 상태 항목 추가: ${status.id}');
    } catch (e) {
      debugPrint('🔥 Firestore 상태 항목 추가 실패: $e');
      rethrow;
    }
  }

  /// 🔄 상태 활성화/비활성화 토글
  @override
  Future<void> updateToggleStatus(String id, bool isActive) async {
    try {
      await _getCollectionRef().doc(id).update({'isActive': isActive});
      debugPrint('🔁 상태 항목 $id → isActive: $isActive');
    } catch (e) {
      debugPrint('🔥 상태 토글 실패: $e');
      rethrow;
    }
  }

  /// ❌ 항목 삭제
  @override
  Future<void> deleteToggleItem(String id) async {
    try {
      await _getCollectionRef().doc(id).delete();
      debugPrint('🗑 상태 항목 삭제 완료: $id');
    } catch (e) {
      debugPrint('🔥 상태 항목 삭제 실패: $e');
      rethrow;
    }
  }
}
