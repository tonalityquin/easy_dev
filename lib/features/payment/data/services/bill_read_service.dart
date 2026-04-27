import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/bill_model.dart';
import '../../domain/models/regular_bill_model.dart';

class BillReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<
      ({
        List<BillModel> generalBills,
        List<RegularBillModel> regularBills,
      })> getBillOnce(String area) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;

    try {
      snapshot = await _firestore
          .collection('bill')
          .where('area', isEqualTo: area)
          .get();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ Firestore bill.read 실패(area=$area): $e');
        debugPrint('stack: $st');
      }
      rethrow;
    }

    final List<BillModel> generalBills = [];
    final List<RegularBillModel> regularBills = [];

    T? tryParse<T>(
      T Function() parse, {
      required String id,
      required String model,
      Map<String, dynamic>? raw,
    }) {
      try {
        return parse();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('⚠️ Bill parse 실패(id=$id, model=$model, area=$area): $e');
          debugPrint('stack: $st');
          if (raw != null) {
            debugPrint('rawKeys(<=20): ${raw.keys.take(20).toList()}');
          }
        }
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
