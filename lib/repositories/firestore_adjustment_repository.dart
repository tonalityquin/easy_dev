import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/adjustment_model.dart';
import 'adjustment_repository.dart';

class FirestoreAdjustmentRepository implements AdjustmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<AdjustmentModel>> getAdjustmentStream(String currentArea) {
    return _firestore
        .collection('adjustment')
        .where('area', isEqualTo: currentArea)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => AdjustmentModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  @override
  Future<void> addAdjustment(AdjustmentModel adjustment) async {
    final docRef = _firestore.collection('adjustment').doc(adjustment.id);
    await docRef.set(adjustment.toMap());
  }

  @override
  Future<void> deleteAdjustment(List<String> ids) async {
    for (String id in ids) {
      await _firestore.collection('adjustment').doc(id).delete();
    }
  }
}
