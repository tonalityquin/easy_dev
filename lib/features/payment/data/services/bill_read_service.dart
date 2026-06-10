import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';

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
      await DevFirebaseDebugDialog.show(
        operation: 'personal.bill.read',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'bill',
          'area': area,
          'query': 'where(area == $area)',
          'filters': 'area == $area',
          'orderBy': 'none',
          'queryShape': 'single-field-equality',
          'compositeIndex': 'not-required-for-this-shape-unless-console-error-requires-it',
        },
      );
      rethrow;
    }

    final List<BillModel> generalBills = [];
    final List<RegularBillModel> regularBills = [];

    Future<T?> tryParse<T>(
      T Function() parse, {
      required String id,
      required String model,
      Map<String, dynamic>? raw,
    }) async {
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
        await DevFirebaseDebugDialog.show(
          operation: 'personal.bill.parse',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'bill',
            'docId': id,
            'model': model,
            'area': area,
            'rawKeys': raw?.keys.take(40).toList(growable: false),
          },
        );
        return null;
      }
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = (data['type'] as String?) ?? '변동';

      if (type == '정기' || type == '고정') {
        final item = await tryParse<RegularBillModel>(
          () => RegularBillModel.fromMap(doc.id, data),
          id: doc.id,
          model: 'RegularBillModel',
          raw: data,
        );
        if (item != null) regularBills.add(item);
      } else {
        final item = await tryParse<BillModel>(
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
