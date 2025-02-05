import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 사용자 데이터 관리를 위한 UserRepository 인터페이스
abstract class UserRepository {
  /// 사용자 목록을 스트림 형태로 반환
  Stream<List<Map<String, dynamic>>> getUsersStream();

  /// 사용자 추가
  Future<void> addUser(String id, Map<String, dynamic> userData);

  /// 여러 사용자 삭제
  Future<void> deleteUsers(List<String> ids);

  /// 사용자 선택 상태 변경
  Future<void> toggleUserSelection(String id, bool isSelected);

  /// 전화번호로 사용자 조회
  Future<Map<String, dynamic>?> getUserByPhone(String phone);
}

/// Firestore를 사용한 UserRepository 구현
class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔥 Firestore 컬렉션 참조 반환 (중복 코드 제거)
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  /// 사용자 목록을 실시간 스트림으로 반환
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
          'area': data['area']?.toString() ?? '',
          'isSelected': (data['isSelected'] ?? false) == true,
        };
      }).toList();
    });
  }

  /// 사용자 추가
  @override
  Future<void> addUser(String id, Map<String, dynamic> userData) async {
    try {
      await _getCollectionRef().doc(id).set(userData);
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (addUser): ${e.message}");
      throw Exception("Firestore 사용자 추가 실패: ${e.message}");
    } catch (e) {
      debugPrint("❌ 알 수 없는 에러 (addUser): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  /// 여러 사용자 삭제 (병렬 삭제 적용)
  @override
  Future<void> deleteUsers(List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) => _getCollectionRef().doc(id).delete()),
      );
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (deleteUsers): ${e.message}");
      throw Exception("Firestore 사용자 삭제 실패: ${e.message}");
    } catch (e) {
      debugPrint("❌ 알 수 없는 에러 (deleteUsers): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  /// 사용자 선택 상태 변경
  @override
  Future<void> toggleUserSelection(String id, bool isSelected) async {
    try {
      await _getCollectionRef().doc(id).update({
        'isSelected': isSelected,
      });
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (toggleUserSelection): ${e.message}");
      throw Exception("Firestore 상태 업데이트 실패: ${e.message}");
    } catch (e) {
      debugPrint("❌ 알 수 없는 에러 (toggleUserSelection): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  /// 전화번호로 사용자 조회
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
      debugPrint("🔥 Firestore 에러 (getUserByPhone): ${e.message}");
      throw Exception("Firestore 사용자 조회 실패: ${e.message}");
    } catch (e) {
      debugPrint("❌ 알 수 없는 에러 (getUserByPhone): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }
}
