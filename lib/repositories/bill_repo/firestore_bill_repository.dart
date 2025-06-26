import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/bill_model.dart';
import 'bill_repository.dart';

class FirestoreBillRepository implements BillRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ✅ 단발성 Firestore 조회 (.get())
  @override
  Future<List<BillModel>> getBillOnce(String area) async {
    try {
      final snapshot = await _firestore.collection('bill').where('area', isEqualTo: area).get();

      final result = snapshot.docs.map((doc) => BillModel.fromMap(doc.id, doc.data())).toList();

      debugPrint('✅ Firestore 조정 데이터 ${result.length}건 로딩 완료');
      return result;
    } catch (e) {
      debugPrint("🔥 Firestore 단발성 조회 실패: $e");
      rethrow;
    }
  }

  /// ➕ 조정 데이터 추가
  @override
  Future<void> addBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();

    // Null 또는 공백 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    debugPrint("📌 Firestore에 저장할 데이터: $data");

    try {
      await docRef.set(data);
      debugPrint("✅ Firestore 데이터 저장 성공: ${bill.id}");
    } catch (e) {
      debugPrint("🔥 Firestore 저장 실패: $e");
      rethrow;
    }
  }

  /// ❌ 여러 조정 데이터 삭제
  @override
  Future<void> deleteBill(List<String> ids) async {
    final batch = _firestore.batch();
    for (final id in ids) {
      final docRef = _firestore.collection('bill').doc(id);
      batch.delete(docRef);
    }

    try {
      await batch.commit();
      debugPrint("✅ Firestore 조정 데이터 ${ids.length}건 삭제 완료");
    } catch (e) {
      debugPrint("🔥 Firestore 조정 삭제 실패: $e");
      rethrow;
    }
  }
}
