import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/bill_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class BillWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 정산(Bill) 데이터를 Firestore에 추가하거나 업데이트합니다.
  Future<void> addBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();

    // Null 또는 공백 필드 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

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
}
