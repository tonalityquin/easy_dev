import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tablet_model.dart';
import '../../models/user_model.dart';

class UserReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getAreasCollectionRef() {
    return _firestore.collection('areas');
  }

  // ----- Helpers -----

  // handle 정규화 (소문자/trim)
  String _normalizeHandle(String h) => h.trim().toLowerCase();

  // TabletModel -> UserModel 매핑 (phone <= handle)
  UserModel _tabletToUser(TabletModel t) {
    return UserModel(
      id: t.id,
      areas: t.areas,
      currentArea: t.currentArea,
      divisions: t.divisions,
      email: t.email,
      endTime: t.endTime,
      englishSelectedAreaName: t.englishSelectedAreaName,
      fixedHolidays: t.fixedHolidays,
      isSaved: t.isSaved,
      isSelected: t.isSelected,
      isWorking: t.isWorking,
      name: t.name,
      password: t.password,
      phone: t.handle,
      // 🔑 handle을 phone 슬롯에 매핑(현 UI/State 호환)
      position: t.position,
      role: t.role,
      selectedArea: t.selectedArea,
      startTime: t.startTime,
    );
  }

  // ----- Reads -----

  /// 사용자 ID로 조회 (user_accounts)
  Future<UserModel?> getUserById(String userId) async {
    debugPrint("getUserById 호출 → ID: $userId");

    final doc = await _getUserCollectionRef().doc(userId).get();
    if (!doc.exists) {
      debugPrint("DB 문서 없음 → userId=$userId");
      return null;
    }

    final data = doc.data()!;
    debugPrint("DB 문서 조회 성공 → userId=$userId / 데이터: $data");
    return UserModel.fromMap(doc.id, data);
  }

  /// 전화번호로 사용자 조회 (user_accounts)
  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("getUserByPhone, 조회 시작 - phone: $phone");

    try {
      final querySnapshot = await _getUserCollectionRef().where('phone', isEqualTo: phone).limit(1).get();

      debugPrint("조회 완료 - 결과 개수: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        debugPrint("사용자 찾음 - ID: ${doc.id}");
        return UserModel.fromMap(doc.id, doc.data());
      } else {
        debugPrint("DB에 사용자 없음");
      }
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }

    return null;
  }

  /// (옵션) handle로 사용자 조회 (user_accounts) - 호환용
  /// 1) 'handle' 필드가 있으면 우선 검색
  /// 2) 없던 시절 호환: 'phone' == handle 로도 검색
  Future<UserModel?> getUserByHandle(String handle) async {
    final h = _normalizeHandle(handle);
    debugPrint("getUserByHandle, 조회 시작 - handle: $h");

    try {
      var qs = await _getUserCollectionRef().where('handle', isEqualTo: h).limit(1).get();

      if (qs.docs.isEmpty) {
        qs = await _getUserCollectionRef().where('phone', isEqualTo: h).limit(1).get();
      }

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      } else {}
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  /// (A안) handle + areaName(한글 지역명)으로 문서 ID 직조회 (tablet_accounts)
  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName) async {
    final h = _normalizeHandle(handle);
    final name = areaName.trim(); // 한글 지역명 그대로 사용
    final docId = '$h-$name';

    debugPrint("getTabletByHandleAndAreaName, docId: $docId");

    try {
      final snap = await _getTabletCollectionRef().doc(docId).get();
      if (snap.exists && snap.data() != null) {
        return TabletModel.fromMap(snap.id, snap.data()!);
      } else {}
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  /// (옵션) handle로 단건 조회 (tablet_accounts)
  Future<TabletModel?> getTabletByHandle(String handle) async {
    final h = _normalizeHandle(handle);
    debugPrint("getTabletByHandle, 조회 시작 - handle: $h");

    try {
      final qs = await _getTabletCollectionRef().where('handle', isEqualTo: h).limit(1).get();

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return TabletModel.fromMap(doc.id, doc.data());
      } else {}
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  // ----- Cache-first list reads -----

  /// 캐시에서 사용자 리스트 조회 (area 기준)
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

  /// Firestore에서 사용자 새로 조회 후 캐시 갱신 (user_accounts)
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 → $selectedArea');

    final querySnapshot = await _getUserCollectionRef().where('areas', arrayContains: selectedArea).get();

    final users = querySnapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

    await _updateCacheWithUsers(selectedArea, users);
    return users;
  }

  /// Firestore에서 태블릿 새로 조회 후 (UserModel로 변환하여) 캐시 갱신 (tablet_accounts)
  Future<List<UserModel>> refreshTabletsBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 (tablet) → $selectedArea');

    final querySnapshot = await _getTabletCollectionRef().where('areas', arrayContains: selectedArea).get();

    // 1) TabletModel로 파싱
    final tablets = querySnapshot.docs.map((doc) => TabletModel.fromMap(doc.id, doc.data())).toList();

    // 2) UserModel로 변환
    final users = tablets.map(_tabletToUser).toList();

    // 3) 캐시 업데이트 및 반환
    await _updateCacheWithUsers(selectedArea, users);
    return users;
  }

  // ----- areas helpers -----

  /// areas 컬렉션에서 영어 이름 조회
  Future<String?> getEnglishNameByArea(String area, String division) async {
    try {
      final doc = await _getAreasCollectionRef().doc('$division-$area').get();
      if (doc.exists) {
        final name = doc.data()?['englishName'] as String?;
        return name;
      }
    } catch (e) {
      debugPrint("[DEBUG] getEnglishNameByArea 실패: $e");
    }

    return null;
  }

  // ----- Cache ops -----

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
