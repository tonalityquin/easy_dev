import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 정산(Bill) 문서를 삭제합니다.
  /// 현재 구현은 첫 번째 ID만 삭제하며, 단건 삭제에 특화되어 있습니다.
  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final docRef = _firestore.collection('bill').doc(ids.first);

    await FirestoreLogger().log('deleteBill called (id=${ids.first})');

    try {
      await docRef.delete();
      await FirestoreLogger().log('deleteBill success: ${ids.first}');
    } catch (e) {
      await FirestoreLogger().log('deleteBill error: $e');
      rethrow;
    }
  }
}
