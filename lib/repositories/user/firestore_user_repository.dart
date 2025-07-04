import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user_model.dart';
import 'user_repository.dart';

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
    debugPrint("getUserById, 호출됨 → 요청 ID: $userId");

    final doc = await _getCollectionRef().doc(userId).get();
    if (!doc.exists) {
      debugPrint("getUserById, DB 문서 없음 → userId=$userId");
      return null;
    }

    final data = doc.data()!;
    debugPrint("getUserById, DB에서 문서 조회 성공 → userId=$userId / 데이터: $data");

    return UserModel.fromMap(doc.id, data);
  }

  @override
  Future<void> updateLoadCurrentArea(String phone, String area, String currentArea) async {
    final userId = '$phone-$area';
    await _getCollectionRef().doc(userId).update({'currentArea': currentArea});
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

    await _getCollectionRef().doc(userId).update(updates);
  }

  @override
  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("getUserByPhone, 사용자 조회 시작 - phone: $phone");

    try {
      final querySnapshot = await _getCollectionRef().where('phone', isEqualTo: phone).get();

      debugPrint("getUserByPhone, 조회 완료 - 결과 개수: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        debugPrint("getUserByPhone, 사용자 찾음 - ID: ${doc.id}, 데이터: ${doc.data()}");

        return UserModel.fromMap(doc.id, doc.data());
      } else {
        debugPrint("getUserByPhone, DB에서 해당 전화번호 사용자를 찾을 수 없음");
      }
    } catch (e) {
      debugPrint("getUserByPhone, DB에서 사용자 조회 중 예외 발생: $e");
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

    await _getCollectionRef().doc(userId).update(updates);
  }

  @override
  Future<void> areaPickerCurrentArea(String phone, String area, String currentArea) async {
    final userId = '$phone-$area';
    await _getCollectionRef().doc(userId).update({'currentArea': currentArea});
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

    await _getCollectionRef().doc(userId).update(updates);
  }

  @override
  Future<void> addUserCard(UserModel user) async {
    await _getCollectionRef().doc(user.id).set(user.toMap());
  }

  @override
  Future<void> updateUser(UserModel user) async {
    await _getCollectionRef().doc(user.id).set(user.toMap());
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    for (final id in ids) {
      await _getCollectionRef().doc(id).delete();
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

    final querySnapshot = await _getCollectionRef().where('areas', arrayContains: selectedArea).get();

    final users = querySnapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
    await _updateCacheWithUsers(selectedArea, users);
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
    await prefs.setInt(
      cacheTsKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    debugPrint('✅ 캐시 갱신 완료 → $selectedArea (${users.length}명)');
  }

  @override
  Future<String?> getEnglishNameByArea(String area, String division) async {
    try {
      final doc = await _getAreasCollectionRef().doc('$division-$area').get();
      if (doc.exists) return doc.data()?['englishName'] as String?;
    } catch (e) {
      debugPrint("[DEBUG] getEnglishNameByArea 실패: $e");
    }
    return null;
  }
}
