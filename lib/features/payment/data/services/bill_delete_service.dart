import '../../../../app/diagnostics/firebase_activity_meter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  
  
  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final String targetId = ids.first;
    final docRef = _firestore.collection('bill').doc(targetId);

    try {
      
      

      
      await docRef.delete().trackFirestore('DELETE', 'features/payment/data/services/bill_delete_service.dart', collection: 'bill');

      
    } catch (_) {
      
      rethrow;
    }
  }
}
