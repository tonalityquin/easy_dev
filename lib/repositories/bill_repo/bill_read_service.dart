import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class BillReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 특정 지역의 정산 데이터를 단발성으로 조회합니다.
  Future<({
  List<BillModel> generalBills,
  List<RegularBillModel> regularBills,
  })> getBillOnce(String area) async {
    await FirestoreLogger().log('getBillOnce called (area=$area)');
    try {
      final snapshot = await _firestore
          .collection('bill')
          .where('area', isEqualTo: area)
          .get();

      List<BillModel> generalBills = [];
      List<RegularBillModel> regularBills = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final type = data['type'] ?? '변동'; // 기본값은 '변동'

        if (type == '고정') {
          try {
            regularBills.add(RegularBillModel.fromMap(doc.id, data));
          } catch (e) {
            await FirestoreLogger().log('⚠️ RegularBillModel 변환 실패: $e');
          }
        } else {
          try {
            generalBills.add(BillModel.fromMap(doc.id, data));
          } catch (e) {
            await FirestoreLogger().log('⚠️ BillModel 변환 실패: $e');
          }
        }
      }

      await FirestoreLogger().log(
        'getBillOnce success: ${generalBills.length} 변동, ${regularBills.length} 고정 로드됨',
      );

      return (generalBills: generalBills, regularBills: regularBills);
    } catch (e) {
      await FirestoreLogger().log('getBillOnce error: $e');
      rethrow;
    }
  }
}
