import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class BillWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addNormalBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap()..putIfAbsent('type', () => '변동');

    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    await FirestoreLogger().log('addNormalBill called (id=${bill.id}, data=$data)');

    try {
      await docRef.set(data);
      debugPrint("✅ Firestore 일반 정산 저장 성공: ${bill.id}");
      await FirestoreLogger().log('addNormalBill success: ${bill.id}');
    } catch (e) {
      debugPrint("🔥 Firestore 일반 정산 저장 실패: $e");
      await FirestoreLogger().log('addNormalBill error: $e');
      rethrow;
    }
  }

  Future<void> addRegularBill(RegularBillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();

    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    await FirestoreLogger().log('addRegularBill called (id=${bill.id}, data=$data)');

    try {
      await docRef.set(data);
      debugPrint("✅ Firestore 정기 정산 저장 성공: ${bill.id}");
      await FirestoreLogger().log('addRegularBill success: ${bill.id}');
    } catch (e) {
      debugPrint("🔥 Firestore 정기 정산 저장 실패: $e");
      await FirestoreLogger().log('addRegularBill error: $e');
      rethrow;
    }
  }
}
