import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

abstract class UserRepository {
  Stream<List<Map<String, dynamic>>> getUsersStream();

  Stream<Map<String, dynamic>?> listenToUserStatus(String phone);

  Future<Map<String, dynamic>?> getUserByPhone(String phone);

  Future<void> addUser(String id, Map<String, dynamic> userData);

  Future<void> toggleUserSelection(String id, bool isSelected);

  Future<void> deleteUsers(List<String> ids);

  Future<void> updateWorkStatus(String phone, String area, bool isWorking); // 🔹 area 추가
}

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  @override
  Stream<List<Map<String, dynamic>>> getUsersStream() {
    return _getCollectionRef().snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? '',
          'phone': data['phone']?.toString() ?? '',
          'email': data['email']?.toString() ?? '',
          'role': data['role']?.toString() ?? '',
          'password': data['password']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'isSelected': (data['isSelected'] ?? false) == true,
          'isWorking': data['isWorking'] ?? false, // 🔹 Firestore에서 출근 상태 추가
        };
      }).toList();
    });
  }

  Stream<Map<String, dynamic>?> listenToUserStatus(String phone) {
    return _getCollectionRef()
        .doc(phone)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }


  @override
  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    try {
      final querySnapshot = await _getCollectionRef().where('phone', isEqualTo: phone).get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return doc.data();
      }
      return null;
    } on FirebaseException catch (e) {
      debugPrint("Firestore 에러 (getUserByPhone): ${e.message}");
      throw Exception("Firestore 사용자 조회 실패: ${e.message}");
    } catch (e) {
      debugPrint("알 수 없는 에러 (getUserByPhone): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> updateWorkStatus(String phone, String area, bool isWorking) async {
    final userId = '$phone-$area'; // 🔹 Firestore 문서 ID에 area 추가

    try {
      await _getCollectionRef().doc(userId).update({'isWorking': isWorking});
    } on FirebaseException catch (e) {
      debugPrint("Firestore 에러 (updateWorkStatus): ${e.message}");
      throw Exception("Firestore 출근 상태 업데이트 실패: ${e.message}");
    }
  }


  @override
  Future<void> addUser(String id, Map<String, dynamic> userData) async {
    try {
      await _getCollectionRef().doc(id).set(userData);
    } on FirebaseException catch (e) {
      debugPrint("Firestore 에러 (addUser): ${e.message}");
      throw Exception("Firestore 사용자 추가 실패: ${e.message}");
    } catch (e) {
      debugPrint("알 수 없는 에러 (addUser): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    try {
      await _getCollectionRef().doc(id).update({
        'isSelected': isSelected,
      });
    } on FirebaseException catch (e) {
      debugPrint("Firestore 에러 (toggleUserSelection): ${e.message}");
      throw Exception("Firestore 상태 업데이트 실패: ${e.message}");
    } catch (e) {
      debugPrint("알 수 없는 에러 (toggleUserSelection): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) => _getCollectionRef().doc(id).delete()),
      );
    } on FirebaseException catch (e) {
      debugPrint("Firestore 에러 (deleteUsers): ${e.message}");
      throw Exception("Firestore 사용자 삭제 실패: ${e.message}");
    } catch (e) {
      debugPrint("알 수 없는 에러 (deleteUsers): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }
}
