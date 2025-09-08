import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter/material.dart';

import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import '../../screens/stub_package/debug_package/debug_firestore_logger.dart';

class BillWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addNormalBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap()..putIfAbsent('type', () => '변동');

    // null/빈 문자열 제거
    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint("✅ Firestore 일반 정산 저장 성공: ${bill.id}");
    } catch (e, st) {
      debugPrint("🔥 Firestore 일반 정산 저장 실패: $e");
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
        await DebugFirestoreLogger().log(payload, level: 'error');
      } catch (_) {
        // 로깅 실패는 무시
      }
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
      debugPrint("✅ Firestore 정기 정산 저장 성공: ${bill.id}");
    } catch (e, st) {
      debugPrint("🔥 Firestore 정기 정산 저장 실패: $e");
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
        await DebugFirestoreLogger().log(payload, level: 'error');
      } catch (_) {
        // 로깅 실패는 무시
      }
      rethrow;
    }
  }
}
