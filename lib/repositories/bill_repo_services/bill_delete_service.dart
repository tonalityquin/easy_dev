import 'package:cloud_firestore/cloud_firestore.dart';

class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final docRef = _firestore.collection('bill').doc(ids.first);

    try {
      await docRef.delete();
    } catch (e) {
      rethrow;
    }
  }
}
