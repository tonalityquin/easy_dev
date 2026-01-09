// lib/repositories/user_repo_services/user_read_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tablet_model.dart';
import '../../models/user_model.dart';
import '../../utils/usage/usage_reporter.dart';

class UserReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getUserShowCollectionRef() {
    return _firestore.collection('user_accounts_show');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getAreasCollectionRef() {
    return _firestore.collection('areas');
  }

  // ----- Helpers -----
  String _normalizeHandle(String h) => h.trim().toLowerCase();

  // userId / tabletId는 '<handle-or-phone>-<area>' 규칙 가정
  String _inferAreaFromHyphenId(String id) {
    final idx = id.lastIndexOf('-');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }

  String _showDocId(String division, String area) {
    final d = division.trim().isEmpty ? 'unknownDivision' : division.trim();
    final a = area.trim().isEmpty ? 'unknownArea' : area.trim();
    return '$d-$a';
  }

  /*String _areaFromDoc(Map<String, dynamic>? data, String id) {
    final d = data ?? const <String, dynamic>{};
    final ca = d['currentArea'] as String?;
    final sa = d['selectedArea'] as String?;
    return (ca?.trim().isNotEmpty == true)
        ? ca!.trim()
        : (sa?.trim().isNotEmpty == true)
            ? sa!.trim()
            : _inferAreaFromHyphenId(id);
  }*/

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
      phone: t.handle, // 🔑 handle을 phone 슬롯에 매핑
      position: t.position,
      role: t.role,
      selectedArea: t.selectedArea,
      startTime: t.startTime,
    );
  }

  // ----- In-memory cache for englishName -----
  static final Map<String, String?> _englishNameMemCache = {};

  String _enKey(String division, String area) => 'englishName_${division}_$area';

  // ----- Reads: single -----
  Future<UserModel?> getUserById(String userId) async {
    debugPrint("getUserById 호출 → ID: $userId");
    try {
      final doc = await _getUserCollectionRef().doc(userId).get();

      /*final area = _areaFromDoc(doc.data(), userId);
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'UserReadService.getUserById',
      );*/

      if (!doc.exists) {
        debugPrint("DB 문서 없음 → userId=$userId");
        return null;
      }
      return UserModel.fromMap(doc.id, doc.data()!);
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("getUserByPhone, 조회 시작 - phone: $phone");
    try {
      final querySnapshot = await _getUserCollectionRef().where('phone', isEqualTo: phone).limit(1).get();

      /*final n = querySnapshot.docs.isEmpty ? 1 : querySnapshot.docs.length;
      final area = querySnapshot.docs.isNotEmpty
          ? _areaFromDoc(querySnapshot.docs.first.data(), querySnapshot.docs.first.id)
          : 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: n,
        source: 'UserReadService.getUserByPhone',
      );*/

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거 (기존 정책: null 반환 유지)
      return null;
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  Future<UserModel?> getUserByHandle(String handle) async {
    final h = _normalizeHandle(handle);
    debugPrint("getUserByHandle, 조회 시작 - handle: $h");
    try {
      var qs = await _getUserCollectionRef().where('handle', isEqualTo: h).limit(1).get();
      if (qs.docs.isEmpty) {
        qs = await _getUserCollectionRef().where('phone', isEqualTo: h).limit(1).get();
      }

      /*final n = qs.docs.isEmpty ? 1 : qs.docs.length;
      final area = qs.docs.isNotEmpty ? _areaFromDoc(qs.docs.first.data(), qs.docs.first.id) : 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: n,
        source: 'UserReadService.getUserByHandle',
      );*/

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거 (기존 정책: null 반환 유지)
      return null;
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName) async {
    final h = _normalizeHandle(handle);
    final name = areaName.trim();
    final docId = '$h-$name';

    debugPrint("getTabletByHandleAndAreaName, docId: $docId");

    try {
      final snap = await _getTabletCollectionRef().doc(docId).get();

      // read 1회 보고
      await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(docId),
        action: 'read',
        n: 1,
        source: 'UserReadService.getTabletByHandleAndAreaName',
      );

      if (snap.exists && snap.data() != null) {
        return TabletModel.fromMap(snap.id, snap.data()!);
      }
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거 (기존 정책: null 반환 유지)
      return null;
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  Future<TabletModel?> getTabletByHandle(String handle) async {
    final h = _normalizeHandle(handle);
    debugPrint("getTabletByHandle, 조회 시작 - handle: $h");

    try {
      final qs = await _getTabletCollectionRef().where('handle', isEqualTo: h).limit(1).get();

      final n = qs.docs.isEmpty ? 1 : qs.docs.length;
      final area = qs.docs.isNotEmpty ? _inferAreaFromHyphenId(qs.docs.first.id) : 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: n,
        source: 'UserReadService.getTabletByHandle',
      );

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return TabletModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거 (기존 정책: null 반환 유지)
      return null;
    } catch (e) {
      debugPrint("DB 조회 중 예외 발생: $e");
    }
    return null;
  }

  // ----- Cache-first list reads -----

  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea) async {
    final cacheKey = 'users_$selectedArea';
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => UserModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ users 캐시 디코딩 실패: $e → 캐시 비움');
        await clearUserCache(selectedArea);
      }
    }
    return [];
  }

  Future<List<UserModel>> getTabletsByAreaOnceWithCache(String selectedArea) async {
    final cacheKey = 'tablets_$selectedArea';
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => UserModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ tablets 캐시 디코딩 실패: $e → 캐시 비움');
        await clearTabletCache(selectedArea);
      }
    }
    return [];
  }

  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 (users) → $selectedArea');

    try {
      final querySnapshot = await _getUserCollectionRef().where('areas', arrayContains: selectedArea).get();

      final users = querySnapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

      /*final n = users.isEmpty ? 1 : users.length;
      await UsageReporter.instance.report(
        area: selectedArea,
        action: 'read',
        n: n,
        source: 'UserReadService.refreshUsersBySelectedArea',
      );*/

      await updateCacheWithUsers(selectedArea, users);
      return users;
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  Future<List<UserModel>> refreshUsersByDivisionAreaFromShow(String division, String area) async {
    final docId = _showDocId(division, area);
    debugPrint('🔥 Firestore 호출 시작 (users_show) → $division / $area → docId=$docId');

    try {
      final usersRef = _getUserShowCollectionRef().doc(docId).collection('users');
      final snap = await usersRef.get(); // ✅ 1회 get

      final users = snap.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList(growable: false);

      // 캐시 키 정책을 기존과 동일하게(area 기준) 유지
      await updateCacheWithUsers(area.trim(), users);
      return users;
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } catch (e) {
      debugPrint("refreshUsersByDivisionAreaFromShow 예외: $e");
      rethrow;
    }
  }

  Future<List<UserModel>> refreshTabletsBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 (tablet) → $selectedArea');

    try {
      final querySnapshot = await _getTabletCollectionRef().where('areas', arrayContains: selectedArea).get();

      // TabletModel → UserModel 변환
      final tablets = querySnapshot.docs.map((doc) => TabletModel.fromMap(doc.id, doc.data())).toList();
      final users = tablets.map(_tabletToUser).toList();

      final n = users.isEmpty ? 1 : users.length;
      await UsageReporter.instance.report(
        area: selectedArea,
        action: 'read',
        n: n,
        source: 'UserReadService.refreshTabletsBySelectedArea',
      );

      await updateCacheWithTablets(selectedArea, users);
      return users;
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  // ----- areas helpers with cache -----
  Future<String?> getEnglishNameByArea(String area, String division) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _enKey(division.trim(), area.trim());

    // 1) 메모리 캐시
    if (_englishNameMemCache.containsKey(key)) {
      return _englishNameMemCache[key];
    }

    // 2) 디스크 캐시
    final disk = prefs.getString(key);
    if (disk != null) {
      _englishNameMemCache[key] = disk;
      return disk;
    }

    // 3) Firestore
    try {
      final doc = await _getAreasCollectionRef().doc('${division.trim()}-${area.trim()}').get();
      String? name;
      if (doc.exists) {
        name = doc.data()?['englishName'] as String?;
      }

      // read 1회
      /*await UsageReporter.instance.report(
        area: area.isNotEmpty ? area : 'unknown',
        action: 'read',
        n: 1,
        source: 'UserReadService.getEnglishNameByArea',
      );*/

      // 캐시 저장(널도 저장해 둬서 재쿼리 방지)
      _englishNameMemCache[key] = name;
      if (name != null) {
        await prefs.setString(key, name);
      }
      return name;
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      return null;
    } catch (e) {
      debugPrint("[DEBUG] getEnglishNameByArea 실패: $e");
      return null;
    }
  }

  // ----- Cache ops -----
  Future<void> clearUserCache(String selectedArea) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('users_$selectedArea');
    await prefs.remove('users_${selectedArea}_ts');
    debugPrint('🧹 사용자 캐시 초기화 → $selectedArea');
  }

  Future<void> clearTabletCache(String selectedArea) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tablets_$selectedArea');
    await prefs.remove('tablets_${selectedArea}_ts');
    debugPrint('🧹 태블릿 캐시 초기화 → $selectedArea');
  }

  Future<void> updateCacheWithUsers(String selectedArea, List<UserModel> users) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = json.encode(users.map((u) => u.toMapWithId()).toList());
    await prefs.setString('users_$selectedArea', jsonData);
    await prefs.setInt('users_${selectedArea}_ts', DateTime.now().millisecondsSinceEpoch);
    debugPrint('✅ users 캐시 갱신 → $selectedArea (${users.length})');
  }

  Future<void> updateCacheWithTablets(String selectedArea, List<UserModel> usersAsTablets) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = json.encode(usersAsTablets.map((u) => u.toMapWithId()).toList());
    await prefs.setString('tablets_$selectedArea', jsonData);
    await prefs.setInt('tablets_${selectedArea}_ts', DateTime.now().millisecondsSinceEpoch);
    debugPrint('✅ tablets 캐시 갱신 → $selectedArea (${usersAsTablets.length})');
  }
}
