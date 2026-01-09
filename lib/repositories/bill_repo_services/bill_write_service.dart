import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // debugPrint

import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
// import '../../utils/usage_reporter.dart';

class BillWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addNormalBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap()..putIfAbsent('type', () => '변동');

    // null/빈 문자열 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint("✅ 일반 정산 저장 성공: ${bill.id}");

      /*final area = (data['area'] ?? bill.area ?? 'unknown') as String;
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'BillWriteService.addNormalBill',
      );*/
    } catch (e, st) {
      // ✅ DebugDatabaseLogger 로직 제거
      debugPrint("🔥 일반 정산 저장 실패: $e");
      debugPrint("stack: $st");
      rethrow;
    }
  }

  Future<void> addRegularBill(RegularBillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();

    // null/빈 문자열 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint("✅ 정기 정산 저장 성공: ${bill.id}");

      /*final area = (data['area'] ?? bill.area ?? 'unknown') as String;
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'BillWriteService.addRegularBill',
      );*/
    } catch (e, st) {
      // ✅ DebugDatabaseLogger 로직 제거
      debugPrint("🔥 정기 정산 저장 실패: $e");
      debugPrint("stack: $st");
      rethrow;
    }
  }
}
