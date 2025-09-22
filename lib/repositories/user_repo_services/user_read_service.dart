// lib/repositories/user_repo_services/user_read_service.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tablet_model.dart';
import '../../models/user_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart';

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
  String _normalizeHandle(String h) => h.trim().toLowerCase();

  // userId / tabletId는 '<handle-or-phone>-<area>' 규칙 가정
  String _inferAreaFromHyphenId(String id) {
    final idx = id.lastIndexOf('-');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }

  String _areaFromDoc(Map<String, dynamic>? data, String id) {
    // 우선순위: currentArea → selectedArea → id suffix
    final d = data ?? const <String, dynamic>{};
    final ca = d['currentArea'] as String?;
    final sa = d['selectedArea'] as String?;
    return (ca?.trim().isNotEmpty == true)
        ? ca!.trim()
        : (sa?.trim().isNotEmpty == true)
        ? sa!.trim()
        : _inferAreaFromHyphenId(id);
  }

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

  // ----- Streams -----
  Stream<List<UserModel>> watchUsersBySelectedArea(String selectedArea) {
    final q = _getUserCollectionRef().where('selectedArea', isEqualTo: selectedArea);

    // 구독 시작 비용은 간단히 read 1로 보고
    // ignore: unawaited_futures
    UsageReporter.instance.report(
      area: selectedArea.isNotEmpty ? selectedArea : 'unknown',
      action: 'read',
      n: 1,
      source: 'UserReadService.watchUsersBySelectedArea',
    );

    return q.snapshots().handleError((e, st) async {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.watchBySelectedArea',
          'collection': 'user_accounts',
          'filters': {'selectedArea': selectedArea},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'watch', 'error'],
        }, level: 'error');
      } catch (_) {}
    }).map((snap) => snap.docs.map((d) => UserModel.fromMap(d.id, d.data())).toList());
  }

  // ----- Reads: single -----
  Future<UserModel?> getUserById(String userId) async {
    debugPrint("getUserById 호출 → ID: $userId");
    try {
      final doc = await _getUserCollectionRef().doc(userId).get();

      // read 1회 보고 (존재 여부에 상관없이)
      final area = _areaFromDoc(doc.data(), userId);
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'UserReadService.getUserById',
      );

      if (!doc.exists) {
        debugPrint("DB 문서 없음 → userId=$userId");
        return null;
      }
      return UserModel.fromMap(doc.id, doc.data()!);
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.getById',
          'collection': 'user_accounts',
          'docId': userId,
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'getById', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<UserModel?> getUserByPhone(String phone) async {
    debugPrint("getUserByPhone, 조회 시작 - phone: $phone");
    try {
      final querySnapshot =
      await _getUserCollectionRef().where('phone', isEqualTo: phone).limit(1).get();

      // read 보고: 결과가 0이어도 1로 보정
      final n = querySnapshot.docs.isEmpty ? 1 : querySnapshot.docs.length;
      final area = querySnapshot.docs.isNotEmpty
          ? _areaFromDoc(querySnapshot.docs.first.data(), querySnapshot.docs.first.id)
          : 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: n,
        source: 'UserReadService.getUserByPhone',
      );

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.getByPhone',
          'collection': 'user_accounts',
          'filters': {'phone': phone},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'getByPhone', 'error'],
        }, level: 'error');
      } catch (_) {}
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

      final n = qs.docs.isEmpty ? 1 : qs.docs.length;
      final area =
      qs.docs.isNotEmpty ? _areaFromDoc(qs.docs.first.data(), qs.docs.first.id) : 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: n,
        source: 'UserReadService.getUserByHandle',
      );

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return UserModel.fromMap(doc.id, doc.data());
      }
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.getByHandle',
          'collection': 'user_accounts',
          'filters': {'handle': h},
          'fallbackFilters': {'phone': h},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'getByHandle', 'error'],
        }, level: 'error');
      } catch (_) {}
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
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.getByHandleAndAreaName',
          'collection': 'tablet_accounts',
          'docId': docId,
          'inputs': {'handle': h, 'areaName': name},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'getByHandleAndAreaName', 'error'],
        }, level: 'error');
      } catch (_) {}
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
      final area =
      qs.docs.isNotEmpty ? _inferAreaFromHyphenId(qs.docs.first.id) : 'unknown';
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
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.getByHandle',
          'collection': 'tablet_accounts',
          'filters': {'handle': h},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'getByHandle', 'error'],
        }, level: 'error');
      } catch (_) {}
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
      final querySnapshot =
      await _getUserCollectionRef().where('areas', arrayContains: selectedArea).get();

      final users =
      querySnapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

      // read 보고: 결과 수(없으면 1)
      final n = users.isEmpty ? 1 : users.length;
      await UsageReporter.instance.report(
        area: selectedArea,
        action: 'read',
        n: n,
        source: 'UserReadService.refreshUsersBySelectedArea',
      );

      await updateCacheWithUsers(selectedArea, users);
      return users;
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.refreshByArea',
          'collection': 'user_accounts',
          'filters': {'areas_contains': selectedArea},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'refreshByArea', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<List<UserModel>> refreshTabletsBySelectedArea(String selectedArea) async {
    debugPrint('🔥 Firestore 호출 시작 (tablet) → $selectedArea');

    try {
      final querySnapshot =
      await _getTabletCollectionRef().where('areas', arrayContains: selectedArea).get();

      // TabletModel → UserModel 변환
      final tablets =
      querySnapshot.docs.map((doc) => TabletModel.fromMap(doc.id, doc.data())).toList();
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
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.refreshByArea',
          'collection': 'tablet_accounts',
          'filters': {'areas_contains': selectedArea},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'refreshByArea', 'error'],
        }, level: 'error');
      } catch (_) {}
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
      await UsageReporter.instance.report(
        area: area.isNotEmpty ? area : 'unknown',
        action: 'read',
        n: 1,
        source: 'UserReadService.getEnglishNameByArea',
      );

      // 캐시 저장(널도 저장해 둬서 재쿼리 방지)
      _englishNameMemCache[key] = name;
      if (name != null) {
        await prefs.setString(key, name);
      }
      return name;
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'areas.getEnglishName',
          'collection': 'areas',
          'docId': '${division.trim()}-${area.trim()}',
          'inputs': {'area': area, 'division': division},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['areas', 'getEnglishName', 'error'],
        }, level: 'error');
      } catch (_) {}
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
