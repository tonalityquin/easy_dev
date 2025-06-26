import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/status_model.dart';
import 'status_repository.dart';

class FirestoreStatusRepository implements StatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  /// 🔗 컬렉션 참조 반환
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(collectionName);
  }

  /// ✅ 단발성 조회 (.get())
  @override
  Future<List<StatusModel>> getStatusesOnce(String area) async {
    try {
      final snapshot = await _getCollectionRef().where('area', isEqualTo: area).get();

      final result = snapshot.docs.map((doc) => StatusModel.fromMap(doc.id, doc.data())).toList();

      debugPrint('✅ Firestore 상태 ${result.length}건 로딩 완료');
      return result;
    } catch (e) {
      debugPrint('🔥 Firestore 상태 단발성 조회 실패: $e');
      rethrow;
    }
  }

  /// ✨ 캐싱 우선 상태 조회
  @override
  Future<List<StatusModel>> getStatusesOnceWithCache(String area) async {
    final cacheKey = 'statuses_$area';
    final cacheTsKey = 'statuses_${area}_ts';
    final prefs = await SharedPreferences.getInstance();

    final cachedJson = prefs.getString(cacheKey);
    final cacheTs = prefs.getInt(cacheTsKey) ?? 0;
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(cacheTs);

    // 🕰 캐시 유효기간 1시간
    const expiry = Duration(hours: 1);
    final isCacheValid = DateTime.now().difference(cacheTime) < expiry;

    if (cachedJson != null && isCacheValid) {
      try {
        debugPrint('✅ 상태 캐시 반환: $area (${DateTime.now().difference(cacheTime).inMinutes}분 경과)');
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => StatusModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ 상태 캐시 디코딩 실패 → Firestore 호출: $e');
      }
    }

    debugPrint('🔥 Firestore 호출 시작 → $area');
    final snapshot = await _getCollectionRef().where('area', isEqualTo: area).get();
    final statuses = snapshot.docs.map((doc) => StatusModel.fromMap(doc.id, doc.data())).toList();

    await _updateCacheWithStatuses(area, statuses); // 캐시 갱신
    return statuses;
  }

  /// ➕ 상태 항목 추가
  @override
  Future<void> addToggleItem(StatusModel status) async {
    final docRef = _getCollectionRef().doc(status.id); // ID 명시
    final data = status.toFirestoreMap();

    data.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await docRef.set(data);
      debugPrint('✅ Firestore 상태 항목 추가: ${status.id}');
      // Firestore 호출 후 캐시 갱신
      await refreshCacheForArea(status.area);
    } catch (e) {
      debugPrint('🔥 Firestore 상태 항목 추가 실패: $e');
      rethrow;
    }
  }

  /// 🔄 상태 활성화/비활성화 토글
  @override
  Future<void> updateToggleStatus(String id, bool isActive) async {
    try {
      await _getCollectionRef().doc(id).update({'isActive': isActive});
      debugPrint('🔁 상태 토글: $id → isActive: $isActive');
      final doc = await _getCollectionRef().doc(id).get();
      if (doc.exists) {
        final data = doc.data()!;
        await refreshCacheForArea(data['area']);
      }
    } catch (e) {
      debugPrint('🔥 상태 토글 실패: $e');
      rethrow;
    }
  }

  /// ❌ 상태 항목 삭제
  @override
  Future<void> deleteToggleItem(String id) async {
    try {
      final doc = await _getCollectionRef().doc(id).get();
      if (doc.exists) {
        final data = doc.data()!;
        await _getCollectionRef().doc(id).delete();
        debugPrint('🗑 상태 항목 삭제 완료: $id');

        // Firestore 호출 후 캐시 갱신
        await refreshCacheForArea(data['area']);
      }
    } catch (e) {
      debugPrint('🔥 상태 항목 삭제 실패: $e');
      rethrow;
    }
  }

  /// 🧠 캐시 갱신 (shared_preferences)
  Future<void> _updateCacheWithStatuses(String area, List<StatusModel> statuses) async {
    final cacheKey = 'statuses_$area';
    final cacheTsKey = 'statuses_${area}_ts';
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      cacheKey,
      json.encode(
        statuses.map((status) => status.toMapWithId()).toList(),
      ),
    );

    await prefs.setInt(
      cacheTsKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    debugPrint('✅ 상태 캐시 갱신 완료 → $area (${statuses.length}개)');
  }

  /// 🔄 Firestore 호출 후 캐시 새로 고침 트리거
  Future<void> refreshCacheForArea(String area) async {
    debugPrint('🔄 캐시 새로 고침 트리거 → $area');
    final snapshot = await _getCollectionRef().where('area', isEqualTo: area).get();

    final statuses = snapshot.docs.map((doc) => StatusModel.fromMap(doc.id, doc.data())).toList();
    await _updateCacheWithStatuses(area, statuses);
  }
}
