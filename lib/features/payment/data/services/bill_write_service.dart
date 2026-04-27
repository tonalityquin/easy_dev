import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/bill_model.dart';
import '../../domain/models/regular_bill_model.dart';

class BillWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addNormalBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap()..putIfAbsent('type', () => '변동');

    data.removeWhere(
        (key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint("✅ 일반 정산 저장 성공: ${bill.id}");
    } catch (e, st) {
      debugPrint("🔥 일반 정산 저장 실패: $e");
      debugPrint("stack: $st");
      rethrow;
    }
  }

  Future<void> addRegularBill(RegularBillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();

    data.removeWhere(
        (key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint("✅ 정기 정산 저장 성공: ${bill.id}");
    } catch (e, st) {
      debugPrint("🔥 정기 정산 저장 실패: $e");
      debugPrint("stack: $st");
      rethrow;
    }
  }
}
