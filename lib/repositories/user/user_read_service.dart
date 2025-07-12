import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class UserReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getAreasCollectionRef() {
    return _firestore.collection('areas');
  }

  /// 사용자 ID로 조회
  Future<UserModel?> getUserById(String userId) async {
    debugPrint("getUserById 호출 → ID: $userId");
    await FirestoreLogger().log('getUserById called: $userId');

    final doc = await _getUserCollectionRef().doc(userId).get();
    if (!doc.exists) {
      debugPrint("DB 문서 없음 → userId=$userId");
      await FirestoreLogger().log('getUserById not found: $userId');
      return null;
    }

    final data = doc.data()!;
    debugPrint("DB 문서 조회 성공 → userId=$userId / 데이터: $data");
    await FirestoreLogger().log('getUserById success: $userId');
    return UserModel.fromMap(doc.id, data);
  }

  /// 전화번호로 사용자 조회
  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("getUserByPhone, 조회 시작 - phone: $phone");
    await FirestoreLogger().log('getUserByPhone called: $phone');

    try {
      final querySnapshot = await _getUserCollectionRef()
          .where('phone', isEqualTo: phone)
          .get();

      debugPrint("조회 완료 - 결과 개수: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        debugPrint("사용자 찾음 - ID: ${doc.id}");
        await FirestoreLogger().log('getUserByPhone success: ${doc.id}');
        return UserModel.fromMap(doc.id, doc.data());
      } else {
        debugPrint("DB에 사용자 없음");
        await FirestoreLogger().log('getUserByPhone not found: $phone');
      }
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
      await FirestoreLogger().log('getUserByPhone error: $e');
    }

    return null;
  }

  /// 캐시에서 사용자 리스트 조회
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea) async {
    final cacheKey = 'users_$selectedArea';
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        debugPrint('✅ 캐시 반환: $selectedArea');
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => UserModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ 캐시 디코딩 실패: $e → 캐시 비움');
        await clearUserCache(selectedArea);
      }
    }
    return [];
  }

  /// Firestore에서 사용자 새로 조회 후 캐시 갱신
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 → $selectedArea');
    await FirestoreLogger().log('refreshUsersBySelectedArea called: $selectedArea');

    final querySnapshot = await _getUserCollectionRef()
        .where('areas', arrayContains: selectedArea)
        .get();

    final users = querySnapshot.docs
        .map((doc) => UserModel.fromMap(doc.id, doc.data()))
        .toList();

    await _updateCacheWithUsers(selectedArea, users);
    await FirestoreLogger().log('refreshUsersBySelectedArea success: ${users.length} users loaded');
    return users;
  }

  /// areas 컬렉션에서 영어 이름 조회
  Future<String?> getEnglishNameByArea(String area, String division) async {
    await FirestoreLogger().log('getEnglishNameByArea called: $division-$area');

    try {
      final doc = await _getAreasCollectionRef().doc('$division-$area').get();
      if (doc.exists) {
        final name = doc.data()?['englishName'] as String?;
        await FirestoreLogger().log('getEnglishNameByArea success: $name');
        return name;
      }
    } catch (e) {
      debugPrint("[DEBUG] getEnglishNameByArea 실패: $e");
      await FirestoreLogger().log('getEnglishNameByArea error: $e');
    }

    return null;
  }

  /// 캐시 제거
  Future<void> clearUserCache(String selectedArea) async {
    final cacheKey = 'users_$selectedArea';
    final prefs = await SharedPreferences.getInstance();
    final cacheTsKey = 'users_${selectedArea}_ts';

    await prefs.remove(cacheKey);
    await prefs.remove(cacheTsKey);

    debugPrint('🧹 캐시 수동 초기화 완료 → $selectedArea');
  }

  Future<void> _updateCacheWithUsers(String selectedArea, List<UserModel> users) async {
    final cacheKey = 'users_$selectedArea';
    final cacheTsKey = 'users_${selectedArea}_ts';
    final prefs = await SharedPreferences.getInstance();

    final jsonData = json.encode(users.map((user) => user.toMapWithId()).toList());
    await prefs.setString(cacheKey, jsonData);
    await prefs.setInt(cacheTsKey, DateTime.now().millisecondsSinceEpoch);

    debugPrint('✅ 캐시 갱신 완료 → $selectedArea (${users.length}명)');
  }
}
