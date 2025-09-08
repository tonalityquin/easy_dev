import 'package:flutter/foundation.dart'; // debugPrint, kDebugMode
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';

class BillReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<({
  List<BillModel> generalBills,
  List<RegularBillModel> regularBills,
  })> getBillOnce(String area) async {
    final snapshot =
    await _firestore.collection('bill').where('area', isEqualTo: area).get();

    final List<BillModel> generalBills = [];
    final List<RegularBillModel> regularBills = [];

    // 안전 파서: 실패 시 null 반환 + 디버그 로그
    T? tryParse<T>(T Function() parse, {required String id}) {
      try {
        return parse();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Bill parse 실패(id=$id): $e');
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
        );
        if (item != null) regularBills.add(item);
      } else {
        final item = tryParse<BillModel>(
              () => BillModel.fromMap(doc.id, data),
          id: doc.id,
        );
        if (item != null) generalBills.add(item);
      }
    }

    return (generalBills: generalBills, regularBills: regularBills);
  }
}
