import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import 'user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  @override
  Stream<List<UserModel>> getUsersStream() {
    return _getCollectionRef().snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  @override
  Stream<UserModel?> listenToUserStatus(String phone) {
    return _getCollectionRef().doc(phone).snapshots().map((doc) =>
    doc.exists ? UserModel.fromMap(doc.id, doc.data()!) : null
    );
  }

  @override
  Future<UserModel?> getUserByPhone(String phone) async {
    print("[DEBUG] Firestore 사용자 조회 시작 - phone: $phone");

    try {
      final querySnapshot = await _getCollectionRef().where('phone', isEqualTo: phone).get();

      print("[DEBUG] Firestore 조회 완료 - 결과 개수: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        print("[DEBUG] 사용자 찾음 - ID: ${doc.id}, 데이터: ${doc.data()}");

        return UserModel.fromMap(doc.id, doc.data());
      } else {
        print("[DEBUG] Firestore에서 해당 전화번호 사용자를 찾을 수 없음");
      }
    } catch (e) {
      print("[DEBUG] Firestore 사용자 조회 중 예외 발생: $e");
    }

    return null;
  }


  @override
  Future<void> addUser(UserModel user) async {
    await _getCollectionRef().doc(user.id).set(user.toMap());
  }

  @override
  Future<void> updateWorkStatus(String phone, String area, bool isWorking) async {
    final userId = '$phone-$area';
    await _getCollectionRef().doc(userId).update({'isWorking': isWorking});
  }

  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    await _getCollectionRef().doc(id).update({'isSelected': isSelected});
  }

  Future<UserModel?> getUserById(String userId) async {
    final doc = await _firestore.collection('user_accounts').doc(userId).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.id, doc.data()!);
  }


  @override
  Future<void> deleteUsers(List<String> ids) async {
    for (String id in ids) {
      await _getCollectionRef().doc(id).delete();
    }
  }
}
