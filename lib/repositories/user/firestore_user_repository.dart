import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
    return _getCollectionRef()
        .doc(phone)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromMap(doc.id, doc.data()!) : null);
  }

  @override
  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("[DEBUG] Firestore 사용자 조회 시작 - phone: $phone");

    try {
      final querySnapshot = await _getCollectionRef().where('phone', isEqualTo: phone).get();

      debugPrint("[DEBUG] Firestore 조회 완료 - 결과 개수: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        debugPrint("[DEBUG] 사용자 찾음 - ID: ${doc.id}, 데이터: ${doc.data()}");

        return UserModel.fromMap(doc.id, doc.data());
      } else {
        debugPrint("[DEBUG] Firestore에서 해당 전화번호 사용자를 찾을 수 없음");
      }
    } catch (e) {
      debugPrint("[DEBUG] Firestore 사용자 조회 중 예외 발생: $e");
    }

    return null;
  }

  @override
  Future<void> addUser(UserModel user) async {
    await _getCollectionRef().doc(user.id).set(user.toMap());
  }

  @override
  Future<void> updateUserStatus(String phone, String area, {bool? isWorking, bool? isSaved}) async {
    final userId = '$phone-$area';

    Map<String, dynamic> updates = {};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _getCollectionRef().doc(userId).update(updates);
  }

  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    await _getCollectionRef().doc(id).update({'isSelected': isSelected});
  }

  // ✅ 추가된 메서드 (JSON 없이 데이터 직접 매핑)
  @override
  Future<UserModel?> getUserById(String userId) async {
    final doc = await _getCollectionRef().doc(userId).get();
    if (!doc.exists) return null;

    return UserModel(
      id: doc.id,
      name: doc['name'] ?? '',
      phone: doc['phone'] ?? '',
      email: doc['email'] ?? '',
      role: doc['role'] ?? '',
      password: doc['password'] ?? '',
      area: doc['area'] ?? '',
      isSelected: doc['isSelected'] ?? false,
      isWorking: doc['isWorking'] ?? false,
      isSaved: doc['isSaved'] ?? false,
    );
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    for (String id in ids) {
      await _getCollectionRef().doc(id).delete();
    }
  }
}
