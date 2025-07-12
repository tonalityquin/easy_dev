import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/bill_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class BillReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 특정 지역의 조정(Bill) 데이터를 단발성으로 조회합니다.
  Future<List<BillModel>> getBillOnce(String area) async {
    await FirestoreLogger().log('getBillOnce called (area=$area)');
    try {
      final snapshot = await _firestore
          .collection('bill')
          .where('area', isEqualTo: area)
          .get();

      final result = snapshot.docs
          .map((doc) => BillModel.fromMap(doc.id, doc.data()))
          .toList();

      await FirestoreLogger()
          .log('getBillOnce success: ${result.length} items loaded');
      return result;
    } catch (e) {
      await FirestoreLogger().log('getBillOnce error: $e');
      rethrow;
    }
  }
}
