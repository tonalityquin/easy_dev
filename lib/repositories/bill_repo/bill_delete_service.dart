import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_package/debugs/firestore_logger.dart';

class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
