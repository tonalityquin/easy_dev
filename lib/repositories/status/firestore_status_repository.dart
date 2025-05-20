import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/status_model.dart';
import 'status_repository.dart';

class FirestoreStatusRepository implements StatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  /// 🔗 statusToggles 컬렉션 참조 반환
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(collectionName);
  }

  /// 🔁 기존 실시간 스트림 방식
  @override
  Stream<List<StatusModel>> getStatusStream(String area) {
    return _getCollectionRef()
        .where('area', isEqualTo: area)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => StatusModel.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  /// ✅ 새로 추가된 단발성 조회 방식 (.get())
  @override
  Future<List<StatusModel>> getStatusesOnce(String area) async {
    try {
      final snapshot = await _getCollectionRef()
          .where('area', isEqualTo: area)
          .get();

      return snapshot.docs
          .map((doc) => StatusModel.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('🔥 Firestore status 단발성 조회 실패: $e');
      rethrow;
    }
  }

  /// ✅ 새 항목 추가
  @override
  Future<void> addToggleItem(StatusModel status) async {
    final docRef = _getCollectionRef().doc();
    await docRef.set(status.toMap());
  }

  /// ✅ 항목 상태 업데이트
  @override
  Future<void> updateToggleStatus(String id, bool isActive) async {
    await _getCollectionRef().doc(id).update({'isActive': isActive});
  }

  /// ✅ 항목 삭제
  @override
  Future<void> deleteToggleItem(String id) async {
    await _getCollectionRef().doc(id).delete();
  }
}
