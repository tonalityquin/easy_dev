import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user_model.dart';
import 'user_repository.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart'; // ✅ FirestoreLogger import

class FirestoreUserRepository implements UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getAreasCollectionRef() {
    return _firestore.collection('areas');
  }

  @override
  Future<UserModel?> getUserById(String userId) async {
    debugPrint("getUserById 호출 → ID: $userId");
    await FirestoreLogger().log('getUserById called: $userId');

    final doc = await _getCollectionRef().doc(userId).get();
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

  @override
  Future<void> updateLoadCurrentArea(String phone, String area, String currentArea) async {
    final userId = '$phone-$area';
    await FirestoreLogger().log('updateLoadCurrentArea called: $userId → $currentArea');

    await _getCollectionRef().doc(userId).update({'currentArea': currentArea});
    await FirestoreLogger().log('updateLoadCurrentArea success: $userId');
  }

  @override
  Future<void> updateLoadUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final userId = '$phone-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await FirestoreLogger().log('updateLoadUserStatus called: $userId → $updates');
    await _getCollectionRef().doc(userId).update(updates);
    await FirestoreLogger().log('updateLoadUserStatus success: $userId');
  }

  @override
  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("getUserByPhone, 조회 시작 - phone: $phone");
    await FirestoreLogger().log('getUserByPhone called: $phone');

    try {
      final querySnapshot = await _getCollectionRef()
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

  @override
  Future<void> updateLogOutUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final userId = '$phone-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await FirestoreLogger().log('updateLogOutUserStatus called: $userId → $updates');
    await _getCollectionRef().doc(userId).update(updates);
    await FirestoreLogger().log('updateLogOutUserStatus success: $userId');
  }

  @override
  Future<void> areaPickerCurrentArea(String phone, String area, String currentArea) async {
    final userId = '$phone-$area';
    await FirestoreLogger().log('areaPickerCurrentArea called: $userId → $currentArea');

    await _getCollectionRef().doc(userId).update({'currentArea': currentArea});
    await FirestoreLogger().log('areaPickerCurrentArea success: $userId');
  }

  @override
  Future<void> updateWorkingUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final userId = '$phone-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await FirestoreLogger().log('updateWorkingUserStatus called: $userId → $updates');
    await _getCollectionRef().doc(userId).update(updates);
    await FirestoreLogger().log('updateWorkingUserStatus success: $userId');
  }

  @override
  Future<void> addUserCard(UserModel user) async {
    await FirestoreLogger().log('addUserCard called: ${user.id}');
    await _getCollectionRef().doc(user.id).set(user.toMap());
    await FirestoreLogger().log('addUserCard success: ${user.id}');
  }

  @override
  Future<void> updateUser(UserModel user) async {
    await FirestoreLogger().log('updateUser called: ${user.id}');
    await _getCollectionRef().doc(user.id).set(user.toMap());
    await FirestoreLogger().log('updateUser success: ${user.id}');
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    for (final id in ids) {
      await FirestoreLogger().log('deleteUser called: $id');
      await _getCollectionRef().doc(id).delete();
      await FirestoreLogger().log('deleteUser success: $id');
    }
  }

  /// ✅ 캐시에서만 읽기 (Firestore 호출 없음)
  @override
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

  /// 🔄 Firestore 호출 및 캐시 갱신
  @override
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 → $selectedArea');
    await FirestoreLogger().log('refreshUsersBySelectedArea called: $selectedArea');

    final querySnapshot = await _getCollectionRef()
        .where('areas', arrayContains: selectedArea)
        .get();

    final users = querySnapshot.docs
        .map((doc) => UserModel.fromMap(doc.id, doc.data()))
        .toList();

    await _updateCacheWithUsers(selectedArea, users);
    await FirestoreLogger().log('refreshUsersBySelectedArea success: ${users.length} users loaded');
    return users;
  }

  /// 🧹 캐시 수동 초기화
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

  @override
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
}
