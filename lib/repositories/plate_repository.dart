import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/plate_request.dart';

abstract class PlateRepository {
  Stream<List<PlateRequest>> getCollectionStream(String collectionName);
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data);
  Future<void> deleteDocument(String collection, String documentId);
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId);
}

class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<PlateRequest>> getCollectionStream(String collectionName) {
    return _firestore.collection(collectionName).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList();
    });
  }

  @override
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data) async {
    await _firestore.collection(collection).doc(documentId).set(data);
  }

  @override
  Future<void> deleteDocument(String collection, String documentId) async {
    await _firestore.collection(collection).doc(documentId).delete();
  }

  @override
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId) async {
    final doc = await _firestore.collection(collection).doc(documentId).get();
    return doc.exists ? doc.data() : null;
  }
}
