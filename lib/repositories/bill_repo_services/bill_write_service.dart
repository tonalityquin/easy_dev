import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter/material.dart';

import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import '../../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';
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
      debugPrint("🔥 일반 정산 저장 실패: $e");
      // --- 실패 시 Firestore 로거에만 error 레벨 기록 ---
      try {
        final payload = {
          'op': 'bill.write',
          'writeType': 'normal',
          'docPath': docRef.path,
          'docId': bill.id,
          'dataPreview': {
            'keys': data.keys.take(30).toList(),
            'len': data.length,
            'type': data['type'],
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['bill', 'write', 'normal', 'error'],
        };
        await DebugDatabaseLogger().log(payload, level: 'error');
      } catch (_) {}
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
      debugPrint("🔥 정기 정산 저장 실패: $e");
      // --- 실패 시 Firestore 로거에만 error 레벨 기록 ---
      try {
        final payload = {
          'op': 'bill.write',
          'writeType': 'regular',
          'docPath': docRef.path,
          'docId': bill.id,
          'dataPreview': {
            'keys': data.keys.take(30).toList(),
            'len': data.length,
            'type': data['type'],
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['bill', 'write', 'regular', 'error'],
        };
        await DebugDatabaseLogger().log(payload, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
