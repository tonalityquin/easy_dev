import 'package:cloud_firestore/cloud_firestore.dart';

/// **UserRepository 인터페이스**
abstract class UserRepository {
  /// 사용자 목록 스트림 반환
  Stream<List<Map<String, dynamic>>> getUsersStream();

  /// 사용자 추가
  Future<void> addUser(String id, Map<String, dynamic> userData);

  /// 사용자 삭제
  Future<void> deleteUsers(List<String> ids);

  /// 사용자 선택 상태 토글
  Future<void> toggleUserSelection(String id, bool isSelected);

  /// 전화번호로 사용자 조회 (추가된 메서드)
  Future<Map<String, dynamic>?> getUserByPhone(String phone);
}

/// **Firestore 기반 UserRepository 구현체**
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

  @override
  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    try {
      final querySnapshot = await _firestore
          .collection('user_accounts')
          .where('phone', isEqualTo: phone)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return doc.data();
      }
    } catch (e) {
      rethrow;
    }
    return null; // 사용자 데이터가 없을 경우 null 반환
  }
}
