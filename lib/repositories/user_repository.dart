import 'package:cloud_firestore/cloud_firestore.dart';

abstract class UserRepository {
  Stream<List<Map<String, dynamic>>> getUsersStream();
  Future<void> addUser(String id, Map<String, dynamic> userData);
  Future<void> deleteUsers(List<String> ids);
  Future<void> toggleUserSelection(String id, bool isSelected);
}

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Map<String, dynamic>>> getUsersStream() {
    return _firestore.collection('user_accounts').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? '',
          'phone': data['phone']?.toString() ?? '',
          'email': data['email']?.toString() ?? '',
          'role': data['role']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'isSelected': (data['isSelected'] ?? false) == true,
        };
      }).toList();
    });
  }

  @override
  Future<void> addUser(String id, Map<String, dynamic> userData) async {
    try {
      await _firestore.collection('user_accounts').doc(id).set(userData);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    try {
      for (var id in ids) {
        await _firestore.collection('user_accounts').doc(id).delete();
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    try {
      await _firestore.collection('user_accounts').doc(id).update({
        'isSelected': isSelected,
      });
    } catch (e) {
      rethrow;
    }
  }
}
