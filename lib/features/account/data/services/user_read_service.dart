import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/usage/usage_reporter.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';

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

  String _normalizeHandle(String h) => h.trim().toLowerCase();

  String _inferAreaFromHyphenId(String id) {
    final idx = id.lastIndexOf('-');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }

  String _showDocId(String division, String area) {
    final d = division
        .trim()
        .isEmpty ? 'unknownDivision' : division.trim();
    final a = area
        .trim()
        .isEmpty ? 'unknownArea' : area.trim();
    return '$d-$a';
  }

  static final Map<String, String?> _englishNameMemCache = {};

  String _enKey(String division, String area) =>
      'englishName_${division}_$area';

  Future<UserModel?> getUserById(String userId) async {
    debugPrint('getUserById 호출 → ID: $userId');
    try {
      final doc = await _getUserCollectionRef().doc(userId).get();

      if (!doc.exists) {
        debugPrint('DB 문서 없음 → userId=$userId');
        return null;
      }
      return UserModel.fromMap(doc.id, doc.data()!);
    } on FirebaseException {
      rethrow;
    }
  }

  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint('getUserByPhone, 조회 시작 - phone: $phone');
    try {
      final querySnapshot = await _getUserCollectionRef()
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException {
      return null;
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
    }
    return null;
  }

  Future<List<UserModel>> searchUsersByPhone(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return <UserModel>[];

    debugPrint('searchUsersByPhone, 조회 시작 - phone: $trimmed');
    try {
      final querySnapshot = await _getUserCollectionRef()
          .where('phone', isEqualTo: trimmed)
          .limit(10)
          .get();

      return querySnapshot.docs
          .map((doc) => UserModel.fromMap(doc.id, doc.data()))
          .toList(growable: false);
    } on FirebaseException {
      return <UserModel>[];
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
      return <UserModel>[];
    }
  }

  Future<UserModel?> getUserByHandle(String handle) async {
    final h = _normalizeHandle(handle);
    debugPrint('getUserByHandle, 조회 시작 - handle: $h');
    try {
      var qs = await _getUserCollectionRef()
          .where('handle', isEqualTo: h)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) {
        qs = await _getUserCollectionRef()
            .where('phone', isEqualTo: h)
            .limit(1)
            .get();
      }

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException {
      return null;
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
    }
    return null;
  }

  Future<TabletModel?> getTabletByHandleAndAreaName(String handle,
      String areaName) async {
    final h = _normalizeHandle(handle);
    final name = areaName.trim();
    final docId = '$h-$name';

    debugPrint('getTabletByHandleAndAreaName, docId: $docId');

    try {
      final snap = await _getTabletCollectionRef().doc(docId).get();

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
      return null;
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
    }
    return null;
  }

  Future<TabletModel?> getTabletByHandle(String handle) async {
    final h = _normalizeHandle(handle);
    debugPrint('getTabletByHandle, 조회 시작 - handle: $h');

    try {
      final qs = await _getTabletCollectionRef()
          .where('handle', isEqualTo: h)
          .limit(1)
          .get();

      final n = qs.docs.isEmpty ? 1 : qs.docs.length;
      final area = qs.docs.isNotEmpty
          ? _inferAreaFromHyphenId(qs.docs.first.id)
          : 'unknown';
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
      return null;
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
    }
    return null;
  }

  Future<List<UserModel>> getUsersByAreaOnceWithCache(
      String selectedArea) async {
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

  Future<List<TabletModel>> getTabletsByAreaOnceWithCache(
      String selectedArea) async {
    final cacheKey = 'tablets_$selectedArea';
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => TabletModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ tablets 캐시 디코딩 실패: $e → 캐시 비움');
        await clearTabletCache(selectedArea);
      }
    }
    return [];
  }

  Future<List<UserModel>> refreshUsersBySelectedArea(
      String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 (users) → $selectedArea');

    try {
      final querySnapshot = await _getUserCollectionRef()
          .where('areas', arrayContains: selectedArea)
          .get();

      final users = querySnapshot.docs
          .map((doc) => UserModel.fromMap(doc.id, doc.data()))
          .toList();

      await updateCacheWithUsers(selectedArea, users);
      return users;
    } on FirebaseException {
      rethrow;
    }
  }

  Future<List<UserModel>> refreshUsersByDivisionAreaFromShow(String division,
      String area) async {
    final docId = _showDocId(division, area);
    debugPrint(
        '🔥 Firestore 호출 시작 (users_show) → $division / $area → docId=$docId');

    try {
      final usersRef =
      _getUserShowCollectionRef().doc(docId).collection('users');
      final snap = await usersRef.get();

      final users = snap.docs
          .map((doc) => UserModel.fromMap(doc.id, doc.data()))
          .toList(growable: false);

      await updateCacheWithUsers(area.trim(), users);
      return users;
    } on FirebaseException {
      rethrow;
    } catch (e) {
      debugPrint('refreshUsersByDivisionAreaFromShow 예외: $e');
      rethrow;
    }
  }

  Future<List<TabletModel>> refreshTabletsBySelectedArea(
      String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 (tablet) → $selectedArea');

    try {
      final querySnapshot = await _getTabletCollectionRef()
          .where('areas', arrayContains: selectedArea)
          .get();

      final tablets = querySnapshot.docs
          .map((doc) => TabletModel.fromMap(doc.id, doc.data()))
          .toList(growable: false);

      final n = tablets.isEmpty ? 1 : tablets.length;
      await UsageReporter.instance.report(
        area: selectedArea,
        action: 'read',
        n: n,
        source: 'UserReadService.refreshTabletsBySelectedArea',
      );

      await updateCacheWithTablets(selectedArea, tablets);
      return tablets;
    } on FirebaseException {
      rethrow;
    }
  }

  Future<String?> getEnglishNameByArea(String area, String division) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _enKey(division.trim(), area.trim());

    if (_englishNameMemCache.containsKey(key)) {
      return _englishNameMemCache[key];
    }

    final disk = prefs.getString(key);
    if (disk != null) {
      _englishNameMemCache[key] = disk;
      return disk;
    }

    try {
      final doc = await _getAreasCollectionRef()
          .doc('${division.trim()}-${area.trim()}')
          .get();
      String? name;
      if (doc.exists) {
        name = doc.data()?['englishName'] as String?;
      }

      _englishNameMemCache[key] = name;
      if (name != null) {
        await prefs.setString(key, name);
      }
      return name;
    } on FirebaseException {
      return null;
    } catch (e) {
      debugPrint('[DEBUG] getEnglishNameByArea 실패: $e');
      return null;
    }
  }

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

  Future<void> updateCacheWithUsers(String selectedArea,
      List<UserModel> users) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = json.encode(users.map((u) => u.toMapWithId()).toList());
    await prefs.setString('users_$selectedArea', jsonData);
    await prefs.setInt(
        'users_${selectedArea}_ts', DateTime
        .now()
        .millisecondsSinceEpoch);
    debugPrint('✅ users 캐시 갱신 → $selectedArea (${users.length})');
  }

  Future<void> updateCacheWithTablets(String selectedArea,
      List<TabletModel> tablets) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData =
    json.encode(tablets.map((t) => t.toMapWithId()).toList());
    await prefs.setString('tablets_$selectedArea', jsonData);
    await prefs.setInt(
        'tablets_${selectedArea}_ts', DateTime
        .now()
        .millisecondsSinceEpoch);
    debugPrint('✅ tablets 캐시 갱신 → $selectedArea (${tablets.length})');
  }
}
