import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/status_model.dart';
import 'status_repository.dart';

class FirestoreStatusRepository implements StatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(collectionName);
  }

  @override
  Stream<List<StatusModel>> getStatusStream(String area) {
    return _getCollectionRef().where('area', isEqualTo: area).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => StatusModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  @override
  Future<void> addToggleItem(StatusModel status) async {
    final docRef = _getCollectionRef().doc();
    await docRef.set(status.toMap());
  }

  @override
  Future<void> updateToggleStatus(String id, bool isActive) async {
    await _getCollectionRef().doc(id).update({'isActive': isActive});
  }

  @override
  Future<void> deleteToggleItem(String id) async {
    await _getCollectionRef().doc(id).delete();
  }
}
