import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;

class FirestoreFields {
  static const String id = 'id';
  static const String name = 'name';
  static const String phone = 'phone';
  static const String email = 'email';
  static const String role = 'role';
  static const String password = 'password';
  static const String area = 'area';
  static const String isSelected = 'isSelected';
  static const String isWorking = 'isWorking';
}

abstract class UserRepository {
  Stream<List<Map<String, dynamic>>> getUsersStream();

  Stream<Map<String, dynamic>?> listenToUserStatus(String phone);

  Future<Map<String, dynamic>?> getUserByPhone(String phone);

  Future<void> addUser(String id, Map<String, dynamic> userData);

  Future<void> updateWorkStatus(String phone, String area, bool isWorking); // 🔹 area 추가
  Future<void> toggleUserSelection(String id, bool isSelected);

  Future<void> deleteUsers(List<String> ids);
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
          FirestoreFields.id: doc.id,
          FirestoreFields.name: data[FirestoreFields.name]?.toString() ?? '',
          FirestoreFields.phone: data[FirestoreFields.phone]?.toString() ?? '',
          FirestoreFields.email: data[FirestoreFields.email]?.toString() ?? '',
          FirestoreFields.role: data[FirestoreFields.role]?.toString() ?? '',
          FirestoreFields.password: data[FirestoreFields.password]?.toString() ?? '',
          FirestoreFields.area: data[FirestoreFields.area]?.toString() ?? '',
          FirestoreFields.isSelected: (data[FirestoreFields.isSelected] ?? false) == true,
          FirestoreFields.isWorking: data[FirestoreFields.isWorking] ?? false,
        };
      }).toList();
    });
  }

  @override
  Stream<Map<String, dynamic>?> listenToUserStatus(String phone) {
    return _getCollectionRef().doc(phone).snapshots().map((doc) => doc.exists ? doc.data() : null);
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
      dev.log("Firestore 에러 (getUserByPhone): ${e.message}");
      throw Exception("Firestore 사용자 조회 실패: ${e.message}");
    } catch (e) {
      dev.log("알 수 없는 에러 (getUserByPhone): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> addUser(String id, Map<String, dynamic> userData) async {
    try {
      await _getCollectionRef().doc(id).set(userData);
    } on FirebaseException catch (e) {
      dev.log("Firestore 에러 (addUser): ${e.message}");
      throw Exception("Firestore 사용자 추가 실패: ${e.message}");
    } catch (e) {
      dev.log("알 수 없는 에러 (addUser): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> updateWorkStatus(String phone, String area, bool isWorking) async {
    final userId = '$phone-$area'; // 🔹 Firestore 문서 ID에 area 추가

    try {
      await _getCollectionRef().doc(userId).update({'isWorking': isWorking});
    } on FirebaseException catch (e) {
      dev.log("Firestore 에러 (updateWorkStatus): ${e.message}");
      throw Exception("Firestore 출근 상태 업데이트 실패: ${e.message}");
    }
  }

  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    try {
      await _getCollectionRef().doc(id).update({
        'isSelected': isSelected,
      });
    } on FirebaseException catch (e) {
      dev.log("Firestore 에러 (toggleUserSelection): ${e.message}");
      throw Exception("Firestore 상태 업데이트 실패: ${e.message}");
    } catch (e) {
      dev.log("알 수 없는 에러 (toggleUserSelection): $e");
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
      dev.log("Firestore 에러 (deleteUsers): ${e.message}");
      throw Exception("Firestore 사용자 삭제 실패: ${e.message}");
    } catch (e) {
      dev.log("알 수 없는 에러 (deleteUsers): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }
}
