import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../applications/tablet_account_diagnostics.dart';
import '../../../../shared/auth/account_code_number.dart';
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

  String? get _authenticatedCacheScope {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  String _userCacheKey(String selectedArea, {String? companyId}) =>
      'users_v3_${_authenticatedCacheScope ?? 'unauthenticated'}_${companyId ?? ''}_$selectedArea';

  String _tabletCacheKey(String selectedArea, {String? companyId}) =>
      'tablets_v3_${_authenticatedCacheScope ?? 'unauthenticated'}_${companyId ?? ''}_$selectedArea';

  String _showDocId(String division, String area) {
    final d = division
        .trim()
        .isEmpty ? 'unknownDivision' : division.trim();
    final a = area
        .trim()
        .isEmpty ? 'unknownArea' : area.trim();
    return '$d-$a';
  }

  UserModel _userFromShowData(String id, Map<String, dynamic> source) {
    final data = Map<String, dynamic>.from(source);
    data.remove('password');
    return UserModel.fromMap(id, data);
  }

  Future<void> _writeRootActiveState(String id, bool active) async {
    await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => _getUserCollectionRef().doc(id).set(
      <String, dynamic>{'isActive': active},
      SetOptions(merge: true),
    ), source: 'user_read_service.set');
  }

  Future<UserModel> _userFromRootWithActiveState(
    String id,
    Map<String, dynamic> source, {
    GetOptions? viewOptions,
  }) async {
    final user = UserModel.fromMap(id, source);
    if (source['isActive'] is bool) return user;

    final division = user.companyId.trim();
    final area = (user.currentArea ?? '').trim().isNotEmpty
        ? user.currentArea!.trim()
        : (user.selectedArea ?? '').trim().isNotEmpty
            ? user.selectedArea!.trim()
            : user.areas.isNotEmpty
                ? user.areas.first.trim()
                : '';
    if (division.isEmpty || area.isEmpty) {
      debugPrint(
        'user_accounts isActive 확인 실패 → userId=$id reason=assignment_missing',
      );
      try {
        await _writeRootActiveState(id, false);
        debugPrint(
          'user_accounts isActive fail-closed backfill 완료 → userId=$id isActive=false',
        );
      } on FirebaseException catch (e) {
        debugPrint(
          'user_accounts isActive fail-closed backfill 실패 → userId=$id code=${e.code}',
        );
      }
      return user.copyWith(isActive: false);
    }

    try {
      final showRef = _getUserShowCollectionRef()
          .doc(_showDocId(division, area))
          .collection('users')
          .doc(id);
      final showSnap = viewOptions == null
          ? await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => showRef.get(), source: 'user_read_service.get')
          : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => showRef.get(viewOptions), source: 'user_read_service.get');
      final active = showSnap.data()?['isActive'];
      if (active is! bool) {
        debugPrint(
          'user_accounts isActive 확인 실패 → userId=$id reason=view_state_missing',
        );
        try {
          await _writeRootActiveState(id, false);
          debugPrint(
            'user_accounts isActive fail-closed backfill 완료 → userId=$id isActive=false',
          );
        } on FirebaseException catch (e) {
          debugPrint(
            'user_accounts isActive fail-closed backfill 실패 → userId=$id code=${e.code}',
          );
        }
        return user.copyWith(isActive: false);
      }
      try {
        await _writeRootActiveState(id, active);
        debugPrint(
          'user_accounts isActive backfill 완료 → userId=$id isActive=$active',
        );
      } on FirebaseException catch (e) {
        debugPrint(
          'user_accounts isActive backfill 쓰기 실패 → userId=$id code=${e.code}',
        );
      }
      return user.copyWith(isActive: active);
    } on FirebaseException catch (e) {
      debugPrint(
        'user_accounts isActive 확인 실패 → userId=$id code=${e.code}',
      );
      return user.copyWith(isActive: false);
    }
  }

  static final Map<String, String?> _englishNameMemCache = {};

  String _enKey(String division, String area) =>
      'englishName_${division}_$area';

  Future<UserModel?> getUserById(String userId) async {
    debugPrint('getUserById 호출 → ID: $userId');
    try {
      final doc = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef().doc(userId).get(), source: 'user_read_service.get');

      if (!doc.exists) {
        debugPrint('DB 문서 없음 → userId=$userId');
        return null;
      }
      return await _userFromRootWithActiveState(doc.id, doc.data()!);
    } on FirebaseException {
      rethrow;
    }
  }

  Future<UserModel?> getUserByIdFromServer(String userId) async {
    final document = _getUserCollectionRef().doc(userId);
    final auth = FirebaseAuth.instance.currentUser;
    debugPrint(
      '[USER-READ] server_account_get_start document=${document.path} firebaseAuthenticated=${auth != null} googleProvider=${auth?.providerData.any((provider) => provider.providerId == 'google.com') ?? false}',
    );
    try {
      final doc = await FirebaseActivityMonitor.track(
        FirebaseActivityKind.read,
        () => document.get(const GetOptions(source: Source.server)),
        source: 'user_read_service.get',
      );
      debugPrint('[USER-READ] server_account_get_complete document=${document.path} exists=${doc.exists}');
      if (!doc.exists) {
        return null;
      }
      return await _userFromRootWithActiveState(
        doc.id,
        doc.data()!,
        viewOptions: const GetOptions(source: Source.server),
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[USER-READ] server_account_get_failed document=${document.path} code=${error.code}\n$stackTrace');
      rethrow;
    }
  }

  Future<UserModel?> getUserByAccountCode(String accountCode) async {
    final normalized = AccountCodeNumber.normalize(accountCode);
    if (!AccountCodeNumber.isValid(normalized)) return null;
    debugPrint(
      'getUserByAccountCode, 조회 시작 - accountCode: ${AccountCodeNumber.mask(normalized)} source=code_index',
    );
    try {
      final index = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('user_account_codes')
          .doc(normalized).get(const GetOptions(source: Source.server)), source: 'user_read_service.get');
      final accountId = (index.data()?['userId'] ?? '').toString().trim();
      if (accountId.isEmpty || index.data()?['codeNumber'] != normalized) {
        return null;
      }
      final user = await getUserByIdFromServer(accountId);
      if (user == null || user.codeNumber != normalized) return null;
      return user;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'getUserByAccountCode, Firebase 조회 실패 - accountCode: ${AccountCodeNumber.mask(normalized)} code=${error.code} message=${error.message}',
      );
      debugPrint('$stackTrace');
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        'getUserByAccountCode, 조회 예외 - accountCode: ${AccountCodeNumber.mask(normalized)} error=$error',
      );
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<List<UserModel>> searchUsersByCodeNumber(String codeNumber) async {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    if (!AccountCodeNumber.isValid(normalized)) return <UserModel>[];

    debugPrint(
      'searchUsersByCodeNumber, 조회 시작 - codeNumber: ${AccountCodeNumber.mask(normalized)}',
    );
    try {
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef()
          .where('codeNumber', isEqualTo: normalized)
          .limit(10)
          .get(), source: 'user_read_service.get');
      final users = await Future.wait(
        snapshot.docs.map(
          (doc) => _userFromRootWithActiveState(doc.id, doc.data()),
        ),
      );
      return users.toList(growable: false);
    } on FirebaseException {
      return <UserModel>[];
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
      return <UserModel>[];
    }
  }

  Future<List<UserModel>> searchUsersByName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return <UserModel>[];

    debugPrint(
      'searchUsersByName, 조회 시작 - nameLength: ${normalized.length}',
    );
    try {
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef()
          .where('name', isEqualTo: normalized)
          .limit(20)
          .get(), source: 'user_read_service.get');
      final users = await Future.wait(
        snapshot.docs.map(
          (doc) => _userFromRootWithActiveState(doc.id, doc.data()),
        ),
      );
      users.sort((a, b) {
        final areaCompare = (a.selectedArea ?? '').compareTo(b.selectedArea ?? '');
        if (areaCompare != 0) return areaCompare;
        return a.codeNumber.compareTo(b.codeNumber);
      });
      return users.toList(growable: false);
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
      var qs = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef()
          .where('handle', isEqualTo: h)
          .limit(1)
          .get(), source: 'user_read_service.get');
      if (qs.docs.isEmpty) {
        qs = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef()
            .where('codeNumber', isEqualTo: h)
            .limit(1)
            .get(), source: 'user_read_service.get');
      }
      if (qs.docs.isEmpty) {
        qs = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef()
            .where('phone', isEqualTo: h)
            .limit(1)
            .get(), source: 'user_read_service.get');
      }

      if (qs.docs.isNotEmpty) {
        final doc = qs.docs.first;
        return await _userFromRootWithActiveState(doc.id, doc.data());
      }
    } on FirebaseException {
      return null;
    } catch (e) {
      debugPrint('DB 조회 중 예외 발생: $e');
    }
    return null;
  }

  bool _tabletMatchesArea(TabletModel tablet, String areaName) {
    final target = areaName.trim();
    if (target.isEmpty) return false;
    final areas = <String>{
      if ((tablet.selectedArea ?? '').trim().isNotEmpty)
        tablet.selectedArea!.trim(),
      if ((tablet.currentArea ?? '').trim().isNotEmpty)
        tablet.currentArea!.trim(),
      ...tablet.areas.map((value) => value.trim()).where((value) => value.isNotEmpty),
    };
    return areas.contains(target);
  }

  Future<List<TabletModel>> searchTabletsByCodeNumber(
    String codeNumber,
  ) async {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    if (!AccountCodeNumber.isValid(normalized)) return <TabletModel>[];

    final legacyNumeric = RegExp(r'^\d{10,11}$').hasMatch(normalized);
    final fields = <String>[
      'codeNumber',
      if (legacyNumeric) 'phone',
      if (legacyNumeric) 'handle',
    ];

    TabletAccountDiagnostics.record(
      'code_number_candidates_lookup_start',
      meta: <String, Object?>{
        'codeNumber': AccountCodeNumber.mask(normalized),
        'legacyNumeric': legacyNumeric,
        'fields': fields.join(','),
      },
    );

    try {
      final snapshots = await Future.wait(
        fields.map(
          (field) => FirebaseActivityMonitor.track(
              FirebaseActivityKind.read,
              () => _getTabletCollectionRef()
                  .where(field, isEqualTo: normalized)
                  .limit(50)
                  .get(),
              source: 'tablet.account.read',
            ),
        ),
      );
      final byId =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          byId[doc.id] = doc;
        }
      }
      final result = byId.values
          .map((doc) => TabletModel.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      TabletAccountDiagnostics.record(
        'code_number_candidates_lookup_complete',
        meta: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(normalized),
          'legacyNumeric': legacyNumeric,
          'count': result.length,
          'documentIds': result
              .map((tablet) => AccountCodeNumber.maskDocumentId(tablet.id))
              .join(','),
        },
      );
      return result;
    } on FirebaseException catch (e, st) {
      TabletAccountDiagnostics.record(
        'code_number_candidates_lookup_failed',
        meta: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(normalized),
          'legacyNumeric': legacyNumeric,
          'error': e.code,
        },
      );
      await DevFirebaseDebugDialog.show(
        operation: 'tablet_accounts.searchTabletsByCodeNumber',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'tablet_accounts',
          'codeNumber': AccountCodeNumber.mask(normalized),
          'fields': fields.join(','),
          'query': fields
              .map((field) => 'where($field == normalized).limit(50)')
              .join(' | '),
        },
      );
      return <TabletModel>[];
    } catch (e, st) {
      debugPrint('DB 조회 중 예외 발생: $e');
      TabletAccountDiagnostics.record(
        'code_number_candidates_parse_failed',
        meta: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(normalized),
          'legacyNumeric': legacyNumeric,
          'error': e.runtimeType,
        },
      );
      await DevFirebaseDebugDialog.show(
        operation: 'tablet_accounts.searchTabletsByCodeNumber.parse',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'tablet_accounts',
          'codeNumber': AccountCodeNumber.mask(normalized),
          'fields': fields.join(','),
        },
      );
      return <TabletModel>[];
    }
  }

  Future<TabletModel?> getTabletByCodeNumberAndAreaName(
    String codeNumber,
    String areaName,
  ) async {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    final area = areaName.trim();
    if (!AccountCodeNumber.isValid(normalized) || area.isEmpty) {
      return null;
    }
    final documentId = AccountCodeNumber.documentId(
      codeNumber: normalized,
      area: area,
    );
    if (documentId.isEmpty) return null;

    TabletAccountDiagnostics.record(
      'code_number_area_lookup_start',
      meta: <String, Object?>{
        'documentId': AccountCodeNumber.maskDocumentId(documentId),
        'policy': 'codeNumber-area',
      },
    );

    try {
      final direct = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getTabletCollectionRef().doc(documentId).get(), source: 'user_read_service.get');
      if (direct.exists && direct.data() != null) {
        TabletAccountDiagnostics.record(
          'code_number_area_lookup_direct_hit',
          meta: <String, Object?>{
            'documentId': AccountCodeNumber.maskDocumentId(documentId),
          },
        );
        return TabletModel.fromMap(direct.id, direct.data()!);
      }

      final matches = (await searchTabletsByCodeNumber(normalized))
          .where((tablet) => _tabletMatchesArea(tablet, area))
          .toList(growable: false);
      if (matches.length == 1) {
        TabletAccountDiagnostics.record(
          'code_number_area_lookup_candidate_hit',
          meta: <String, Object?>{
            'sourceId': AccountCodeNumber.maskDocumentId(matches.single.id),
            'targetDocumentId': AccountCodeNumber.maskDocumentId(documentId),
          },
        );
        return matches.single;
      }
      if (matches.length > 1) {
        TabletAccountDiagnostics.record(
          'code_number_area_lookup_ambiguous',
          meta: <String, Object?>{
            'targetDocumentId': AccountCodeNumber.maskDocumentId(documentId),
            'count': matches.length,
          },
        );
      } else {
        TabletAccountDiagnostics.record(
          'code_number_area_lookup_miss',
          meta: <String, Object?>{
            'targetDocumentId': AccountCodeNumber.maskDocumentId(documentId),
          },
        );
      }
    } on FirebaseException catch (e, st) {
      TabletAccountDiagnostics.record(
        'code_number_area_lookup_failed',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'error': e.code,
        },
      );
      await DevFirebaseDebugDialog.show(
        operation: 'tablet_accounts.getTabletByCodeNumberAndAreaName',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'tablet_accounts',
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'policy': 'codeNumber-area',
        },
      );
    } catch (e, st) {
      debugPrint('DB 조회 중 예외 발생: $e');
      TabletAccountDiagnostics.record(
        'code_number_area_lookup_parse_failed',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'error': e.runtimeType,
        },
      );
      await DevFirebaseDebugDialog.show(
        operation: 'tablet_accounts.getTabletByCodeNumberAndAreaName.parse',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'tablet_accounts',
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
        },
      );
    }
    return null;
  }

  Future<TabletModel?> getTabletByCodeNumber(String codeNumber) async {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    debugPrint(
      'getTabletByCodeNumber, 조회 시작 - codeNumber=${AccountCodeNumber.mask(normalized)}',
    );
    if (!AccountCodeNumber.isValid(normalized)) return null;

    final matches = await searchTabletsByCodeNumber(normalized);
    if (matches.length == 1) return matches.single;
    if (matches.length > 1) {
      TabletAccountDiagnostics.record(
        'code_number_only_lookup_ambiguous',
        meta: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(normalized),
          'count': matches.length,
        },
      );
    }
    return null;
  }

  Future<List<UserModel>> getUsersByAreaOnceWithCache(
      String selectedArea, {String? companyId}) async {
    if ((companyId ?? '').trim().isEmpty) return <UserModel>[];
    final scope = _authenticatedCacheScope;
    if (scope == null) return <UserModel>[];
    final cacheKey = _userCacheKey(selectedArea, companyId: companyId);
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => UserModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ users 캐시 디코딩 실패: $e → 캐시 비움');
        await clearUserCache(selectedArea, companyId: companyId);
      }
    }
    return [];
  }

  Future<List<TabletModel>> getTabletsByAreaOnceWithCache(
      String selectedArea, {String? companyId}) async {
    if ((companyId ?? '').trim().isEmpty) return <TabletModel>[];
    final scope = _authenticatedCacheScope;
    if (scope == null) return <TabletModel>[];
    final cacheKey = _tabletCacheKey(selectedArea, companyId: companyId);
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        return decoded.map((e) => TabletModel.fromMap(e['id'], e)).toList();
      } catch (e) {
        debugPrint('⚠️ tablets 캐시 디코딩 실패: $e → 캐시 비움');
        await clearTabletCache(selectedArea, companyId: companyId);
      }
    }
    return [];
  }

  Future<List<UserModel>> refreshUsersBySelectedArea(
      String selectedArea, {required String companyId}) async {
    final verifiedCompany = companyId.trim();
    if (verifiedCompany.isEmpty) {
      throw StateError('USER_COMPANY_SCOPE_REQUIRED');
    }
    debugPrint('🔥 Firestore 호출 시작 (users) → $selectedArea');

    try {
      final querySnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef()
          .where('companyId', isEqualTo: verifiedCompany)
          .where('areas', arrayContains: selectedArea)
          .get(), source: 'user_read_service.get');

      final users = await Future.wait(
        querySnapshot.docs.map(
          (doc) => _userFromRootWithActiveState(doc.id, doc.data()),
        ),
      );

      await updateCacheWithUsers(selectedArea, users, companyId: verifiedCompany);
      StatusDialog.recordDebugOperation(
        'user_accounts',
        'area_refresh_completed',
        details: <String, Object?>{'resultCount': users.length},
      );
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
      final snap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => usersRef.get(), source: 'user_read_service.get');

      final users = snap.docs
          .map((doc) => _userFromShowData(doc.id, doc.data()))
          .toList(growable: false);

      await updateCacheWithUsers(area.trim(), users, companyId: division.trim());
      StatusDialog.recordDebugOperation(
        'user_accounts_show',
        'division_area_refresh_completed',
        details: <String, Object?>{'resultCount': users.length},
      );
      return users;
    } on FirebaseException {
      rethrow;
    } catch (e) {
      debugPrint('refreshUsersByDivisionAreaFromShow 예외: $e');
      rethrow;
    }
  }

  Future<List<UserModel>> refreshActiveUsersByDivisionAreaFromShow(
    String division,
    String area,
  ) async {
    final docId = _showDocId(division, area);
    debugPrint(
      'Firestore active users_show 조회 시작 → $division / $area → docId=$docId',
    );

    try {
      final usersRef =
          _getUserShowCollectionRef().doc(docId).collection('users');
      final snap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => usersRef
          .where('isActive', isEqualTo: true)
          .get(), source: 'user_read_service.get');

      final users = snap.docs
          .map((doc) => _userFromShowData(doc.id, doc.data()))
          .toList(growable: false);

      debugPrint(
        'Firestore active users_show 조회 완료 → $division / $area → count=${users.length}',
      );
      return users;
    } on FirebaseException {
      rethrow;
    } catch (e, st) {
      debugPrint(
        'refreshActiveUsersByDivisionAreaFromShow 예외 → $division / $area → $e\nStackTrace:\n$st',
      );
      rethrow;
    }
  }

  Future<List<TabletModel>> refreshTabletsBySelectedArea(
      String selectedArea, {String? companyId}) async {
    final verifiedCompany = (companyId ?? '').trim();
    if (verifiedCompany.isEmpty) {
      throw StateError('TABLET_COMPANY_SCOPE_REQUIRED');
    }
    debugPrint('🔥 Firestore 호출 시작 (tablet) → $selectedArea');

    try {
      final querySnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getTabletCollectionRef()
          .where('companyId', isEqualTo: verifiedCompany)
          .where('areas', arrayContains: selectedArea)
          .get(), source: 'user_read_service.get');

      final tablets = querySnapshot.docs
          .map((doc) => TabletModel.fromMap(doc.id, doc.data()))
          .toList(growable: false);


      await updateCacheWithTablets(selectedArea, tablets, companyId: verifiedCompany);
      StatusDialog.recordDebugOperation(
        'tablet_accounts',
        'area_refresh_completed',
        details: <String, Object?>{
          'resultCount': tablets.length,
          'companyScoped': true,
        },
      );
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
      final doc = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getAreasCollectionRef()
          .doc('${division.trim()}-${area.trim()}')
          .get(), source: 'user_read_service.get');
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

  Future<void> clearUserCache(String selectedArea, {String? companyId}) async {
    if ((companyId ?? '').trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userCacheKey(selectedArea, companyId: companyId));
    await prefs.remove('users_$selectedArea');
    await prefs.remove('users_${selectedArea}_ts');
    await prefs.remove('users_v3_${_authenticatedCacheScope ?? 'unauthenticated'}_${companyId ?? ''}_${selectedArea}_ts');
    debugPrint('🧹 사용자 캐시 초기화 → $selectedArea');
  }

  Future<void> clearTabletCache(String selectedArea, {String? companyId}) async {
    if ((companyId ?? '').trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tabletCacheKey(selectedArea, companyId: companyId));
    await prefs.remove('tablets_$selectedArea');
    await prefs.remove('tablets_${selectedArea}_ts');
    await prefs.remove('tablets_v3_${_authenticatedCacheScope ?? 'unauthenticated'}_${companyId ?? ''}_${selectedArea}_ts');
    debugPrint('🧹 태블릿 캐시 초기화 → $selectedArea');
  }

  Future<void> updateCacheWithUsers(String selectedArea,
      List<UserModel> users, {String? companyId}) async {
    if ((companyId ?? '').trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonData = json.encode(users.map((u) => u.toMapWithId()).toList());
    if (_authenticatedCacheScope == null) return;
    await prefs.setString(_userCacheKey(selectedArea, companyId: companyId), jsonData);
    await prefs.setInt(
        'users_v3_${_authenticatedCacheScope}_${companyId ?? ''}_${selectedArea}_ts', DateTime
        .now()
        .millisecondsSinceEpoch);
    StatusDialog.recordDebugOperation('user_accounts', 'cache_updated',
        details: <String, Object?>{'count': users.length, 'companyScoped': true});
    debugPrint('✅ users 캐시 갱신 → $selectedArea (${users.length})');
  }

  Future<void> updateCacheWithTablets(String selectedArea,
      List<TabletModel> tablets, {String? companyId}) async {
    if ((companyId ?? '').trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonData =
    json.encode(tablets.map((t) => t.toMapWithId()).toList());
    if (_authenticatedCacheScope == null) return;
    await prefs.setString(_tabletCacheKey(selectedArea, companyId: companyId), jsonData);
    await prefs.setInt(
        'tablets_v3_${_authenticatedCacheScope}_${companyId ?? ''}_${selectedArea}_ts', DateTime
        .now()
        .millisecondsSinceEpoch);
    StatusDialog.recordDebugOperation('tablet_accounts', 'cache_updated',
        details: <String, Object?>{'count': tablets.length, 'companyScoped': true});
    debugPrint('✅ tablets 캐시 갱신 → $selectedArea (${tablets.length})');
  }
}
