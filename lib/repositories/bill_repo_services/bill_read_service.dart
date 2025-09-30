import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // debugPrint, kDebugMode
import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart';

class BillReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<
      ({
        List<BillModel> generalBills,
        List<RegularBillModel> regularBills,
      })> getBillOnce(String area) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;

    // --- 파이어스토어 쿼리 실패 로깅 ---
    try {
      snapshot = await _firestore.collection('bill').where('area', isEqualTo: area).get();
    } catch (e, st) {
      try {
        final payload = {
          'op': 'bill.read',
          'collection': 'bill',
          'query': {'area': area},
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['bill', 'read', 'error'],
        };
        await DebugFirestoreLogger().log(payload, level: 'error');
      } catch (_) {}
      rethrow;
    }

    final readN = snapshot.docs.isEmpty ? 1 : snapshot.docs.length;
    await UsageReporter.instance.report(
      area: area,
      action: 'read',
      n: readN,
      source: 'BillReadService.getBillOnce',
    );

    final List<BillModel> generalBills = [];
    final List<RegularBillModel> regularBills = [];

    // 안전 파서: 실패 시 null 반환 + Firestore 에러 로깅
    T? tryParse<T>(
      T Function() parse, {
      required String id,
      required String model, // 'BillModel' | 'RegularBillModel'
      Map<String, dynamic>? raw,
    }) {
      try {
        return parse();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('⚠️ Bill parse 실패(id=$id, model=$model): $e');
        }
        // 동기 컨텍스트라 await 불가 → unawaited 처리
        // ignore: unawaited_futures
        DebugFirestoreLogger().log({
          'op': 'bill.parse',
          'docId': id,
          'model': model,
          'area': area,
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['bill', 'parse', 'error'],
          if (raw != null) 'rawKeys': raw.keys.take(20).toList(),
        }, level: 'error');
        return null;
      }
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = (data['type'] as String?) ?? '변동';

      if (type == '고정') {
        final item = tryParse<RegularBillModel>(
          () => RegularBillModel.fromMap(doc.id, data),
          id: doc.id,
          model: 'RegularBillModel',
          raw: data,
        );
        if (item != null) regularBills.add(item);
      } else {
        final item = tryParse<BillModel>(
          () => BillModel.fromMap(doc.id, data),
          id: doc.id,
          model: 'BillModel',
          raw: data,
        );
        if (item != null) generalBills.add(item);
      }
    }

    return (generalBills: generalBills, regularBills: regularBills);
  }
}
