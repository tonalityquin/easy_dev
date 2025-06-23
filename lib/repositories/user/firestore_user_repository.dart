import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  // 🔍 areas 컬렉션 참조 메서드
  CollectionReference<Map<String, dynamic>> _getAreasCollectionRef() {
    return _firestore.collection('areas');
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
  Future<UserModel?> getUserById(String userId) async {
    debugPrint("📥 getUserById() 호출됨 → 요청 ID: $userId");

    final doc = await _getCollectionRef().doc(userId).get();
    if (!doc.exists) {
      debugPrint("❌ Firestore 문서 없음 → userId=$userId");
      return null;
    }

    final data = doc.data()!;
    debugPrint("✅ Firestore 문서 조회 성공 → userId=$userId / 데이터: $data");

    return UserModel.fromMap(doc.id, data);
  }

  @override
  Future<void> updateCurrentArea(String phone, String area, String currentArea) async {
    final userId = '$phone-$area';
    await _getCollectionRef().doc(userId).update({
      'currentArea': currentArea,
    });
  }

  @override
  Future<void> updateUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  }) async {
    final userId = '$phone-$area';

    Map<String, dynamic> updates = {};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _getCollectionRef().doc(userId).update(updates);
  }

  @override
  Future<void> addUser(UserModel user) async {
    await _getCollectionRef().doc(user.id).set(user.toMap());
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    for (String id in ids) {
      await _getCollectionRef().doc(id).delete();
    }
  }

  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    await _getCollectionRef().doc(id).update({'isSelected': isSelected});
  }

  @override
  Stream<List<UserModel>> getUsersBySelectedAreaStream(String selectedArea) {
    return _getCollectionRef()
        .where('areas', arrayContains: selectedArea)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList());
  }

  // ✨ 추가된 부분: areas 컬렉션에서 englishName 조회
  @override
  Future<String?> getEnglishNameByArea(String area, String division) async {
    try {
      final doc = await _getAreasCollectionRef().doc('$division-$area').get();
      if (doc.exists) {
        return doc.data()?['englishName'] as String?;
      }
    } catch (e) {
      debugPrint("[DEBUG] getEnglishNameByArea 실패: $e");
    }
    return null;
  }

}
