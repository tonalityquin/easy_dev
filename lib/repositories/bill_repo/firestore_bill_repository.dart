import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/bill_model.dart';
import 'bill_repository.dart';
import '../../utils/firestore_logger.dart'; // ✅ FirestoreLogger import

class FirestoreBillRepository implements BillRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<BillModel>> getBillOnce(String area) async {
    await FirestoreLogger().log('getBillOnce called (area=$area)');
    try {
      final snapshot = await _firestore
          .collection('bill')
          .where('area', isEqualTo: area)
          .get();

      final result = snapshot.docs
          .map((doc) => BillModel.fromMap(doc.id, doc.data()))
          .toList();

      debugPrint('✅ Firestore 조정 데이터 ${result.length}건 로딩 완료');
      await FirestoreLogger().log('getBillOnce success: ${result.length} items loaded');
      return result;
    } catch (e) {
      debugPrint("🔥 Firestore 단발성 조회 실패: $e");
      await FirestoreLogger().log('getBillOnce error: $e');
      rethrow;
    }
  }

  @override
  Future<void> addBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();

    // Null 또는 공백 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    debugPrint("📌 Firestore에 저장할 데이터: $data");
    await FirestoreLogger().log('addBill called (id=${bill.id}, data=$data)');

    try {
      await docRef.set(data);
      debugPrint("✅ Firestore 데이터 저장 성공: ${bill.id}");
      await FirestoreLogger().log('addBill success: ${bill.id}');
    } catch (e) {
      debugPrint("🔥 Firestore 저장 실패: $e");
      await FirestoreLogger().log('addBill error: $e');
      rethrow;
    }
  }

  /// 정산 유형 삭제
  @override
  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final docRef = _firestore.collection('bill').doc(ids.first);
    await FirestoreLogger().log('deleteBill called (id=${ids.first})');
    try {
      await docRef.delete();
      debugPrint("✅ Firestore 문서 삭제 성공: ${ids.first}");
      await FirestoreLogger().log('deleteBill success: ${ids.first}');
    } catch (e) {
      debugPrint("🔥 Firestore 문서 삭제 실패: $e");
      await FirestoreLogger().log('deleteBill error: $e');
      rethrow;
    }
  }
}
