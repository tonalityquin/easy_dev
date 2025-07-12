import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class UserWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  /// 사용자 추가
  Future<void> addUserCard(UserModel user) async {
    await FirestoreLogger().log('addUserCard called: ${user.id}');
    await _getUserCollectionRef().doc(user.id).set(user.toMap());
    await FirestoreLogger().log('addUserCard success: ${user.id}');
  }

  /// 사용자 전체 업데이트
  Future<void> updateUser(UserModel user) async {
    await FirestoreLogger().log('updateUser called: ${user.id}');
    await _getUserCollectionRef().doc(user.id).set(user.toMap());
    await FirestoreLogger().log('updateUser success: ${user.id}');
  }

  /// 사용자 삭제 (ID 목록 기준)
  Future<void> deleteUsers(List<String> ids) async {
    for (final id in ids) {
      await FirestoreLogger().log('deleteUser called: $id');
      await _getUserCollectionRef().doc(id).delete();
      await FirestoreLogger().log('deleteUser success: $id');
    }
  }
}
