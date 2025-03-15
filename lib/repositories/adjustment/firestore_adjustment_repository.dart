import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/adjustment_model.dart';
import 'adjustment_repository.dart';

class FirestoreAdjustmentRepository implements AdjustmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<AdjustmentModel>> getAdjustmentStream(String currentArea) {
    return _firestore.collection('adjustment').where('area', isEqualTo: currentArea).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => AdjustmentModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  @override
  Future<void> addAdjustment(AdjustmentModel adjustment) async {
    final docRef = _firestore.collection('adjustment').doc(adjustment.id);
    final data = adjustment.toMap();

    // Null 값이나 잘못된 데이터 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    debugPrint("📌 Firestore에 저장할 데이터: $data");

    try {
      await docRef.set(data, SetOptions(merge: true));
      debugPrint("✅ Firestore 데이터 저장 성공: ${adjustment.id}");
    } catch (e) {
      debugPrint("🔥 Firestore 저장 실패: $e");
      rethrow; // 예외를 다시 throw 하여 상위에서 처리 가능하게 함
    }
  }

  @override
  Future<void> deleteAdjustment(List<String> ids) async {
    for (String id in ids) {
      await _firestore.collection('adjustment').doc(id).delete();
    }
  }
}
