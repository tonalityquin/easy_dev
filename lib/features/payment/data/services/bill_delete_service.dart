import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  
  
  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final String targetId = ids.first;
    final docRef = _firestore.collection('bill').doc(targetId);

    try {
      
      

      
      await FirebaseActivityMonitor.track(FirebaseActivityKind.delete, () => docRef.delete(), source: 'bill_delete_service.delete');

      
    } catch (_) {
      
      rethrow;
    }
  }
}
