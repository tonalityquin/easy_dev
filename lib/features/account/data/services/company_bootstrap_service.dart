import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/auth/google_auth_session.dart';
import '../../../../app/utils/access_gate_diagnostics.dart';
import '../../../dev/application/developer_account_authorization.dart';

class BootstrapCompany {
  const BootstrapCompany({
    required this.id,
    required this.initialized,
    required this.accountExists,
    required this.initialAdminExists,
    required this.codeConsistent,
    required this.showConsistent,
    required this.metaConsistent,
    required this.bootstrapConsistent,
  });

  final String id;
  final bool initialized;
  final bool accountExists;
  final bool initialAdminExists;
  final bool codeConsistent;
  final bool showConsistent;
  final bool metaConsistent;
  final bool bootstrapConsistent;

  bool get needsInitialization => !initialized && !accountExists;
  bool get needsReview => (!initialized && accountExists) ||
      (initialized && (!bootstrapConsistent ||
        (!initialAdminExists && accountExists)));
  bool get needsRecovery => initialized && !needsReview &&
      (!initialAdminExists || !codeConsistent ||
       !showConsistent || !metaConsistent);
  bool get healthy => initialized && !needsRecovery && !needsReview;
}

class BootstrapPreview {
  const BootstrapPreview({
    required this.companies,
    required this.divisions,
    required this.areas,
    required this.areaIds,
    required this.catalogVersion,
  });

  final List<BootstrapCompany> companies;
  final List<String> divisions;
  final List<String> areas;
  final List<String> areaIds;
  final int catalogVersion;

  int get pending => companies.where((company) => company.needsInitialization).length;
  int get recoveryRequired => companies.where((company) => company.needsRecovery).length;
  int get reviewRequired => companies.where((company) => company.needsReview).length;
}

class BootstrapSyncProgress {
  const BootstrapSyncProgress({
    required this.status,
    required this.totalCount,
    required this.completedCount,
    required this.pendingCompanyIds,
  });

  final String status;
  final int totalCount;
  final int completedCount;
  final List<String> pendingCompanyIds;

  bool get needsRetry => status != 'completed' || pendingCompanyIds.isNotEmpty;
}

class CompanyBootstrapService {
  const CompanyBootstrapService();

  static const List<String> allModes = <String>[
    'single', 'double', 'triple', 'minor',
  ];

  static const List<String> initialPermissions = <String>[
    'accounts.read',
    'accounts.create',
    'accounts.update',
    'accounts.delete',
    'accounts.activate',
    'accounts.grantPermissions',
    'sector.manage',
    'location.manage',
    'rule.manage',
    'tablet.manage',
    'bill.manage',
    'monthly.manage',
    'company.manage',
    'voice.delete.any',
    'single.operations.enter',
  ];

  static bool _sameStrings(dynamic left, dynamic right) {
    if (left is! List || right is! List) return false;
    final a = left.map((value) => value.toString()).toList()..sort();
    final b = right.map((value) => value.toString()).toList()..sort();
    return listEquals(a, b);
  }

  static bool _matchesCatalog(
    Map<String, dynamic>? data,
    BootstrapPreview snapshot,
  ) => data != null &&
      data['accessCatalogVersion'] == snapshot.catalogVersion &&
      _sameStrings(data['divisions'], snapshot.divisions) &&
      _sameStrings(data['areas'], snapshot.areas) &&
      _sameStrings(data['areaIds'], snapshot.areaIds) &&
      _sameStrings(data['modes'], allModes);

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static String initialCode(String companyId) {
    if (companyId == 'belivus') return '01090351868';
    final digest = sha256.convert(utf8.encode(companyId)).toString();
    return 'a${digest.substring(0, 9)}1';
  }

  static String initialAccountId(String companyId) =>
      '${initialCode(companyId)}-$companyId';

  static Future<void> requireDeveloper({
    String source = 'initial_setup',
    bool forceAccountSelection = true,
  }) async {
    AccessGateDiagnostics.record('developer_auth_start', source: source);
    final identity = await GoogleAuthSession.instance
        .ensureFirebaseAuthenticatedIdentity(forceAccountSelection: forceAccountSelection);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('INITIAL_SETUP_FIREBASE_AUTH_REQUIRED');
    }
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? <String, dynamic>{};
    final email = (claims['email'] ?? '').toString().trim().toLowerCase();
    final firebase = claims['firebase'];
    final provider = firebase is Map ? firebase['sign_in_provider']?.toString() : null;
    if (identity.normalizedEmail != email ||
        !DeveloperAccountAuthorization.allowedEmails.contains(email) ||
        claims['email_verified'] != true ||
        provider != 'google.com') {
      AccessGateDiagnostics.record(
        'developer_auth_denied', source: source, reason: 'claims_invalid',
      );
      throw StateError('INITIAL_SETUP_DEVELOPER_IDENTITY_REQUIRED');
    }
    final gate = await FirebaseFirestore.instance
        .doc('developer_login_gate/authorization')
        .get(const GetOptions(source: Source.server));
    if (!gate.exists || gate.data()?['enabled'] != true) {
      AccessGateDiagnostics.record(
        'developer_auth_denied', source: source, reason: 'gate_disabled',
      );
      throw StateError('INITIAL_SETUP_DEVELOPER_GATE_DISABLED');
    }
    AccessGateDiagnostics.record('developer_auth_approved', source: source);
  }

  Future<BootstrapPreview> preview() async {
    final snapshots = await Future.wait([
      _firestore.collection('divisions').get(const GetOptions(source: Source.server)),
      _firestore.collection('areas').get(const GetOptions(source: Source.server)),
    ]);
    final divisionDocs = snapshots[0].docs
        .where((doc) => doc.data()['lifecycleStatus'] != 'closed')
        .toList(growable: false);
    final activeCompanyIds = divisionDocs.map((doc) => doc.id).toSet();
    final areaDocs = snapshots[1].docs
        .where((doc) => activeCompanyIds.contains(
            (doc.data()['division'] ?? '').toString()))
        .toList(growable: false);
    final divisions = divisionDocs.map((doc) => doc.id.trim())
        .where((value) => value.isNotEmpty).toSet().toList()..sort();
    final areas = areaDocs.map((doc) => (doc.data()['name'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty).toSet().toList()..sort();
    final areaIds = areaDocs.map((doc) => doc.id).toSet().toList()..sort();
    final catalog = await _firestore.doc('access_catalog/current')
        .get(const GetOptions(source: Source.server));
    final version = catalog.data()?['version'] is int
        ? catalog.data()!['version'] as int : 0;
    final companies = <BootstrapCompany>[];
    for (final company in divisions) {
      final accountId = initialAccountId(company);
      final checks = await Future.wait([
        _firestore.collection('company_bootstrap').doc(company)
            .get(const GetOptions(source: Source.server)),
        _firestore.collection('user_accounts').doc(accountId)
            .get(const GetOptions(source: Source.server)),
        _firestore.collection('user_account_codes').doc(initialCode(company))
            .get(const GetOptions(source: Source.server)),
        _firestore.collection('user_accounts_show').doc('$company-$company')
            .collection('users').doc(accountId)
            .get(const GetOptions(source: Source.server)),
        _firestore.collection('user_accounts_show').doc('$company-$company')
            .get(const GetOptions(source: Source.server)),
      ]);
      final bootstrap = checks[0];
      final admin = checks[1];
      final code = checks[2];
      final show = checks[3];
      final meta = checks[4];
      final general = await _firestore.collection('user_accounts')
          .where('companyId', isEqualTo: company).limit(1)
          .get(const GetOptions(source: Source.server));
      final projections = await _firestore.collection('user_accounts_show')
          .doc('$company-$company').collection('users')
          .get(const GetOptions(source: Source.server));
      final activeCount = projections.docs
          .where((doc) => doc.data()['isActive'] == true).length;
      final inactiveCount = projections.docs.length - activeCount;
      companies.add(BootstrapCompany(
        id: company,
        initialized: bootstrap.exists,
        accountExists: general.docs.isNotEmpty,
        initialAdminExists: admin.exists &&
            admin.data()?['companyId'] == company &&
            admin.data()?['isInitialAdmin'] == true,
        codeConsistent: code.exists &&
            code.data()?['userId'] == accountId &&
            code.data()?['codeNumber'] == initialCode(company) &&
            code.data()?['area'] == company,
        showConsistent: show.exists &&
            show.data()?['companyId'] == company &&
            show.data()?['isInitialAdmin'] == true &&
            show.data()?['codeNumber'] == initialCode(company) &&
            (!admin.exists || (
              _sameStrings(show.data()?['permissionKeys'], admin.data()?['permissionKeys']) &&
              _sameStrings(show.data()?['divisions'], admin.data()?['divisions']) &&
              _sameStrings(show.data()?['areas'], admin.data()?['areas']) &&
              _sameStrings(show.data()?['areaIds'], admin.data()?['areaIds']) &&
              _sameStrings(show.data()?['modes'], admin.data()?['modes']) &&
              show.data()?['accessCatalogVersion'] == admin.data()?['accessCatalogVersion']
            )) &&
            !show.data()!.containsKey('passwordHash') &&
            !show.data()!.containsKey('passwordSalt'),
        metaConsistent: meta.exists &&
            meta.data()?['division'] == company &&
            meta.data()?['area'] == company &&
            meta.data()?['activeCount'] == activeCount &&
            meta.data()?['inactiveCount'] == inactiveCount &&
            meta.data()?['totalCount'] == projections.docs.length,
        bootstrapConsistent: bootstrap.exists &&
            bootstrap.data()?['status'] == 'completed' &&
            bootstrap.data()?['companyId'] == company &&
            bootstrap.data()?['initialAdminAccountId'] == accountId,
      ));
    }
    return BootstrapPreview(
      companies: companies, divisions: divisions, areas: areas,
      areaIds: areaIds, catalogVersion: version,
    );
  }

  Future<BootstrapSyncProgress?> syncProgress(int version) async {
    final document = await _firestore.collection('access_sync_jobs')
        .doc('catalog_$version')
        .get(const GetOptions(source: Source.server));
    final data = document.data();
    if (data == null) return null;
    return BootstrapSyncProgress(
      status: (data['status'] ?? 'pending').toString(),
      totalCount: data['totalCount'] is int ? data['totalCount'] as int : 0,
      completedCount: data['completedCount'] is int
          ? data['completedCount'] as int : 0,
      pendingCompanyIds: (data['pendingCompanyIds'] as List<dynamic>? ??
          const <dynamic>[]).map((value) => value.toString()).toList(),
    );
  }

  static Map<String, dynamic> _accountData({
    required String company,
    required List<String> divisions,
    required List<String> areas,
    required List<String> areaIds,
    int accessCatalogVersion = 0,
    String? password,
  }) {
    final isBelivus = company == 'belivus';
    final code = initialCode(company);
    final suppliedPassword = password?.trim() ?? '';
    if (isBelivus && suppliedPassword.isEmpty) {
      throw StateError('INITIAL_SETUP_BELIVUS_PASSWORD_REQUIRED');
    }
    final salt = isBelivus
        ? sha256.convert(utf8.encode('$company:${DateTime.now().microsecondsSinceEpoch}:$code')).toString()
        : '';
    final passwordHash = isBelivus
        ? sha256.convert(utf8.encode('$salt:$suppliedPassword')).toString()
        : '';
    return <String, dynamic>{
      'name': isBelivus ? '조성오' : '초기 관리자 등록 대기',
      'phone': isBelivus ? code : '',
      'codeNumber': code,
      'email': isBelivus ? 'surge1868@gmail.com' : '',
      'position': isBelivus ? 'PM' : '',
      'companyId': company,
      'divisions': divisions,
      'areas': areas,
      'areaIds': areaIds,
      'accessCatalogVersion': accessCatalogVersion,
      'modes': allModes,
      'currentArea': company,
      'selectedArea': company,
      'englishSelectedAreaName': company,
      'isInitialAdmin': true,
      'permissionKeys': initialPermissions,
      'permissionSchemaVersion': 1,
      'isActive': isBelivus,
      'isSaved': true,
      'isSelected': false,
      'isWorking': isBelivus,
      'accountStatus': isBelivus ? 'active' : 'pending_registration',
      'breakDays': <String>['일'],
      'fixedHolidays': <String>['월', '화', '수', '목', '금', '토'],
      'startTimeByWeekday': <String, dynamic>{
        for (final day in <String>['월', '화', '수', '목', '금', '토']) day: null,
        '일': <String, int>{'hour': 9, 'minute': 0},
      },
      'endTimeByWeekday': <String, dynamic>{
        for (final day in <String>['월', '화', '수', '목', '금', '토']) day: null,
        '일': <String, int>{'hour': 18, 'minute': 0},
      },
      if (isBelivus) 'passwordSalt': salt,
      if (isBelivus) 'passwordHash': passwordHash,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _writeInitialAdmin({
    required Transaction tx,
    required String company,
    required Map<String, dynamic> data,
    required bool createCompany,
    required int expectedCatalogVersion,
    Map<String, dynamic>? divisionData,
    Map<String, dynamic>? areaData,
    Map<String, dynamic>? metaData,
  }) async {
    final accountId = initialAccountId(company);
    final code = initialCode(company);
    final bootstrapRef = _firestore.collection('company_bootstrap').doc(company);
    final userRef = _firestore.collection('user_accounts').doc(accountId);
    final codeRef = _firestore.collection('user_account_codes').doc(code);
    final metaRef = _firestore.collection('user_accounts_show').doc('$company-$company');
    final showRef = metaRef.collection('users').doc(accountId);
    final divisionRef = _firestore.collection('divisions').doc(company);
    final areaRef = _firestore.collection('areas').doc('$company-$company');
    final reads = await Future.wait([
      tx.get(bootstrapRef), tx.get(userRef), tx.get(codeRef),
      tx.get(metaRef), tx.get(showRef),
      tx.get(divisionRef),
      if (createCompany) tx.get(areaRef),
      tx.get(_firestore.doc('access_catalog/current')),
    ]);
    final catalogData = reads.last.data();
    final actualCatalogVersion = catalogData?['version'] is int
        ? catalogData!['version'] as int : 0;
    if (actualCatalogVersion != expectedCatalogVersion) {
      throw StateError('ACCESS_CATALOG_CHANGED');
    }
    if (reads[0].exists || reads[1].exists || reads[2].exists || reads[4].exists) {
      throw StateError('INITIAL_SETUP_ALREADY_INITIALIZED_OR_CONFLICT');
    }
    if (createCompany && (reads[5].exists || reads[6].exists)) {
      throw StateError('INITIAL_SETUP_COMPANY_ALREADY_EXISTS');
    }
    if (!createCompany && (!reads[5].exists ||
        reads[5].data()?['lifecycleStatus'] == 'closed' ||
        reads[5].data()?['lifecycleStatus'] == 'closing' ||
        reads[5].data()?['accountWriteLocked'] == true)) {
      throw StateError('INITIAL_SETUP_COMPANY_NOT_WRITABLE:$company');
    }
    if (createCompany) {
      tx.set(divisionRef, <String, dynamic>{
        ...divisionData!,
        'lifecycleStatus': 'active',
        'accountWriteLocked': false,
      });
      tx.set(areaRef, areaData!);
      tx.set(_firestore.doc('access_catalog/current'), <String, dynamic>{
        'version': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (!createCompany) {
      tx.update(divisionRef, <String, dynamic>{
        'accountWriteVersion': FieldValue.increment(1),
      });
    }
    tx.set(userRef, data);
    tx.set(codeRef, <String, dynamic>{
      'userId': accountId,
      'codeNumber': code,
      'area': company,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final active = data['isActive'] == true ? 1 : 0;
    tx.set(metaRef, <String, dynamic>{
      ...?metaData,
      'division': company,
      'area': company,
      'activeCount': active,
      'inactiveCount': 1 - active,
      'totalCount': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final showData = Map<String, dynamic>.from(data)
      ..remove('passwordHash')
      ..remove('passwordSalt')
      ..remove('password');
    tx.set(showRef, showData);
    tx.set(bootstrapRef, <String, dynamic>{
      'companyId': company,
      'initialAdminAccountId': accountId,
      'status': 'completed',
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<String>> initializeExisting({
    required BootstrapPreview preview,
    String? belivusPassword,
    void Function(String message)? onProgress,
  }) async {
    final completed = <String>[];
    for (final company in preview.companies.where((item) => item.needsInitialization)) {
      final data = _accountData(
        company: company.id,
        divisions: preview.divisions,
        areas: preview.areas,
        areaIds: preview.areaIds,
        accessCatalogVersion: preview.catalogVersion,
        password: belivusPassword,
      );
      await _firestore.runTransaction((tx) async {
        await _writeInitialAdmin(
          tx: tx, company: company.id, data: data,
          createCompany: false,
          expectedCatalogVersion: preview.catalogVersion,
        );
      });
      completed.add(company.id);
      onProgress?.call('${company.id}: 초기 관리자 생성 완료');
      AccessGateDiagnostics.record('bootstrap_created', source: 'launcher_help', group: 'developer');
    }
    return completed;
  }

  Future<List<String>> recoverInitialAdmins({
    required BootstrapPreview preview,
    String? belivusPassword,
    void Function(String message)? onProgress,
  }) async {
    await requireDeveloper(
      source: 'launcher_initial_setup_recovery',
      forceAccountSelection: false,
    );
    final refreshed = await this.preview();
    final selected = preview.companies
        .where((company) => company.needsRecovery)
        .map((company) => company.id).toSet();
    final completed = <String>[];
    for (final company in refreshed.companies.where(
        (item) => selected.contains(item.id) && item.needsRecovery)) {
      final accountId = initialAccountId(company.id);
      final code = initialCode(company.id);
      final bootstrapRef = _firestore.collection('company_bootstrap').doc(company.id);
      final divisionRef = _firestore.collection('divisions').doc(company.id);
      final userRef = _firestore.collection('user_accounts').doc(accountId);
      final codeRef = _firestore.collection('user_account_codes').doc(code);
      final metaRef = _firestore.collection('user_accounts_show')
          .doc('${company.id}-${company.id}');
      final showRef = metaRef.collection('users').doc(accountId);
      final projections = await metaRef.collection('users')
          .limit(2).get(const GetOptions(source: Source.server));
      final otherProjectionExists = projections.docs.any((doc) => doc.id != accountId);
      await _firestore.runTransaction((tx) async {
        final reads = await Future.wait([
          tx.get(bootstrapRef), tx.get(userRef), tx.get(codeRef),
          tx.get(showRef), tx.get(metaRef),
          tx.get(_firestore.doc('access_catalog/current')),
          tx.get(divisionRef),
        ]);
        if (!reads[6].exists ||
            reads[6].data()?['accountWriteLocked'] == true ||
            reads[6].data()?['lifecycleStatus'] == 'closed' ||
            reads[6].data()?['lifecycleStatus'] == 'closing') {
          throw StateError('COMPANY_ACCOUNT_WRITE_BLOCKED:${company.id}');
        }
        final actualVersion = reads[5].data()?['version'] is int
            ? reads[5].data()!['version'] as int : 0;
        if (actualVersion != refreshed.catalogVersion) {
          throw StateError('ACCESS_CATALOG_CHANGED');
        }
        final bootstrap = reads[0];
        final account = reads[1];
        final reserved = reads[2];
        if (!bootstrap.exists ||
            bootstrap.data()?['companyId'] != company.id ||
            bootstrap.data()?['initialAdminAccountId'] != accountId ||
            bootstrap.data()?['status'] != 'completed') {
          throw StateError('INITIAL_SETUP_RECOVERY_BOOTSTRAP_CONFLICT:${company.id}');
        }
        if (account.exists && (account.data()?['companyId'] != company.id ||
            account.data()?['isInitialAdmin'] != true)) {
          throw StateError('INITIAL_SETUP_RECOVERY_ACCOUNT_CONFLICT:${company.id}');
        }
        if (reserved.exists && (reserved.data()?['userId'] != accountId ||
            reserved.data()?['codeNumber'] != code ||
            reserved.data()?['area'] != company.id)) {
          throw StateError('INITIAL_SETUP_RECOVERY_CODE_CONFLICT:${company.id}');
        }
        final data = account.data() ?? _accountData(
          company: company.id,
          divisions: refreshed.divisions,
          areas: refreshed.areas,
          areaIds: refreshed.areaIds,
          accessCatalogVersion: refreshed.catalogVersion,
          password: belivusPassword,
        );
        if (!account.exists) tx.set(userRef, data);
        if (!reserved.exists) {
          tx.set(codeRef, <String, dynamic>{
            'codeNumber': code,
            'userId': accountId,
            'area': company.id,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        final projection = Map<String, dynamic>.from(data)
          ..remove('password')
          ..remove('passwordHash')
          ..remove('passwordSalt');
        tx.set(showRef, projection);
        final previousMeta = reads[4].data();
        final previousShow = reads[3].data();
        if (previousMeta == null && otherProjectionExists) {
          throw StateError('INITIAL_SETUP_META_REBUILD_REQUIRED:${company.id}');
        }
        final currentActive = previousMeta?['activeCount'];
        final currentInactive = previousMeta?['inactiveCount'];
        final currentTotal = previousMeta?['totalCount'];
        if (previousMeta != null && (currentActive is! int ||
            currentInactive is! int || currentTotal is! int ||
            currentActive < 0 || currentInactive < 0 ||
            currentActive + currentInactive != currentTotal)) {
          throw StateError('INITIAL_SETUP_META_REBUILD_REQUIRED:${company.id}');
        }
        final wasActive = previousShow?['isActive'] == true;
        final isActive = data['isActive'] == true;
        final existed = reads[3].exists;
        final deltaActive = (isActive ? 1 : 0) -
            (existed && wasActive ? 1 : 0);
        final deltaInactive = (isActive ? 0 : 1) -
            (existed && !wasActive ? 1 : 0);
        final nextActive = (currentActive is int ? currentActive : 0) + deltaActive;
        final nextInactive = (currentInactive is int ? currentInactive : 0) + deltaInactive;
        if (nextActive < 0 || nextInactive < 0) {
          throw StateError('INITIAL_SETUP_META_REBUILD_REQUIRED:${company.id}');
        }
        tx.set(metaRef, <String, dynamic>{
          'division': company.id,
          'area': company.id,
          'activeCount': nextActive,
          'inactiveCount': nextInactive,
          'totalCount': nextActive + nextInactive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        tx.update(bootstrapRef, <String, dynamic>{
          'recoveryCount': FieldValue.increment(1),
          'lastRecoveryAt': FieldValue.serverTimestamp(),
        });
      });
      completed.add(company.id);
      onProgress?.call('${company.id}: 초기 관리자 표시·집계·예약 문서 복구 완료');
      AccessGateDiagnostics.record(
        'bootstrap_recovered', source: 'launcher_help', group: 'developer',
      );
    }
    return completed;
  }

  Future<void> rebuildAccountCounts({
    required String companyId,
    void Function(String message)? onProgress,
  }) async {
    await requireDeveloper(
      source: 'initial_admin_count_rebuild',
      forceAccountSelection: false,
    );
    final company = companyId.trim();
    if (company.isEmpty) throw StateError('COMPANY_ID_REQUIRED');
    final divisionRef = _firestore.collection('divisions').doc(company);
    final metaRef = _firestore.collection('user_accounts_show')
        .doc('$company-$company');
    final collection = metaRef.collection('users');
    final operationId = DateTime.now().microsecondsSinceEpoch.toString();
    await _firestore.runTransaction((tx) async {
      final division = await tx.get(divisionRef);
      if (!division.exists || division.data()?['lifecycleStatus'] == 'closed' ||
          division.data()?['lifecycleStatus'] == 'closing' ||
          division.data()?['accountWriteLocked'] == true) {
        throw StateError('COMPANY_COUNT_REBUILD_UNAVAILABLE:$company');
      }
      tx.update(divisionRef, <String, dynamic>{
        'accountWriteLocked': true,
        'accountWriteLockId': operationId,
        'accountWriteVersion': FieldValue.increment(1),
      });
    });
    onProgress?.call('$company: 계정 집계 재구축 잠금 적용');
    try {
      final all = await collection.get(const GetOptions(source: Source.server));
      final active = all.docs.where((doc) => doc.data()['isActive'] == true).length;
      final inactive = all.docs.length - active;
      await _firestore.runTransaction((tx) async {
        final division = await tx.get(divisionRef);
        await tx.get(metaRef);
        if (division.data()?['accountWriteLockId'] != operationId ||
            division.data()?['accountWriteLocked'] != true ||
            division.data()?['lifecycleStatus'] == 'closed') {
          throw StateError('COMPANY_COUNT_REBUILD_LOCK_CHANGED:$company');
        }
        tx.set(metaRef, <String, dynamic>{
          'division': company,
          'area': company,
          'activeCount': active,
          'inactiveCount': inactive,
          'totalCount': active + inactive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        tx.update(divisionRef, <String, dynamic>{
          'accountWriteLocked': false,
          'accountWriteLockId': FieldValue.delete(),
          'accountWriteVersion': FieldValue.increment(1),
        });
      });
      onProgress?.call('$company: 활성 $active · 비활성 $inactive 집계 재구축 완료');
    } catch (error) {
      try {
        await _firestore.runTransaction((tx) async {
          final division = await tx.get(divisionRef);
          if (division.data()?['accountWriteLockId'] == operationId &&
              division.data()?['accountWriteLocked'] == true) {
            tx.update(divisionRef, <String, dynamic>{
              'accountWriteLocked': false,
              'accountWriteLockId': FieldValue.delete(),
            });
          }
        });
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> createCompany({
    required String company,
    required Map<String, dynamic> divisionData,
    required Map<String, dynamic> areaData,
    required Map<String, dynamic> metaData,
    String? belivusPassword,
  }) async {
    await requireDeveloper(
      source: 'create_company',
      forceAccountSelection: false,
    );
    final previous = await preview();
    if (previous.divisions.contains(company)) {
      throw StateError('INITIAL_SETUP_COMPANY_ALREADY_EXISTS');
    }
    final companyAreas = <String>{...previous.areas, company}.toList()..sort();
    final companyAreaIds = <String>{...previous.areaIds, '$company-$company'}.toList()..sort();
    final allDivisions = <String>{...previous.divisions, company}.toList()..sort();
    final data = _accountData(
      company: company,
      divisions: allDivisions,
      areas: companyAreas,
      areaIds: companyAreaIds,
      accessCatalogVersion: previous.catalogVersion + 1,
      password: belivusPassword,
    );
    await _firestore.runTransaction((tx) async {
      await _writeInitialAdmin(
        tx: tx,
        company: company,
        data: data,
        createCompany: true,
        expectedCatalogVersion: previous.catalogVersion,
        divisionData: divisionData,
        areaData: areaData,
        metaData: metaData,
      );
    });
    await synchronizeInitialAdmins();
  }

  Future<void> closeCompany({required String company}) async {
    await requireDeveloper(source: 'close_company', forceAccountSelection: false);
    final normalized = company.trim();
    if (normalized.isEmpty) throw StateError('COMPANY_ID_REQUIRED');
    final divisionRef = _firestore.collection('divisions').doc(normalized);
    final bootstrapRef = _firestore.collection('company_bootstrap').doc(normalized);
    final accountId = initialAccountId(normalized);
    final accountRef = _firestore.collection('user_accounts').doc(accountId);
    final metaRef = _firestore.collection('user_accounts_show')
        .doc('$normalized-$normalized');
    final displayRef = metaRef.collection('users').doc(accountId);
    final catalogRef = _firestore.doc('access_catalog/current');
    final divisionBefore = await divisionRef.get(
      const GetOptions(source: Source.server),
    );
    if (!divisionBefore.exists ||
        divisionBefore.data()?['accountWriteLocked'] == true) {
      throw StateError('COMPANY_CLOSE_UNAVAILABLE:$normalized');
    }
    final expectedWriteVersion = divisionBefore.data()?['accountWriteVersion'] is int
        ? divisionBefore.data()!['accountWriteVersion'] as int : 0;
    final dependentTablets = await _firestore.collection('tablet_accounts')
        .where('companyId', isEqualTo: normalized).limit(1)
        .get(const GetOptions(source: Source.server));
    if (dependentTablets.docs.isNotEmpty) {
      throw StateError('COMPANY_CLOSE_RELATED_TABLET_EXISTS');
    }
    final dependentAccounts = await _firestore.collection('user_accounts')
        .where('companyId', isEqualTo: normalized).limit(2)
        .get(const GetOptions(source: Source.server));
    if (dependentAccounts.docs.any((doc) => doc.id != accountId)) {
      throw StateError('COMPANY_CLOSE_RELATED_ACCOUNT_EXISTS');
    }
    await _firestore.runTransaction((tx) async {
      final reads = await Future.wait([
        tx.get(divisionRef), tx.get(bootstrapRef), tx.get(accountRef),
        tx.get(displayRef), tx.get(metaRef), tx.get(catalogRef),
      ]);
      final division = reads[0].data();
      final bootstrap = reads[1].data();
      final account = reads[2].data();
      final meta = reads[4].data();
      final currentWriteVersion = division?['accountWriteVersion'] is int
          ? division!['accountWriteVersion'] as int : 0;
      if (division == null || division['lifecycleStatus'] == 'closed' ||
          division['accountWriteLocked'] == true ||
          currentWriteVersion != expectedWriteVersion) {
        throw StateError('COMPANY_ALREADY_CLOSED_OR_MISSING');
      }
      if (bootstrap == null || bootstrap['status'] != 'completed' ||
          bootstrap['initialAdminAccountId'] != accountId ||
          account == null || account['companyId'] != normalized ||
          account['isInitialAdmin'] != true ||
          !reads[3].exists || meta == null || meta['totalCount'] != 1) {
        throw StateError('COMPANY_CLOSE_INTEGRITY_REVIEW_REQUIRED');
      }
      tx.update(divisionRef, <String, dynamic>{
        'lifecycleStatus': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });
      tx.update(bootstrapRef, <String, dynamic>{
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });
      tx.update(accountRef, <String, dynamic>{
        'isActive': false,
        'accountStatus': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(displayRef, <String, dynamic>{
        'isActive': false,
        'accountStatus': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(metaRef, <String, dynamic>{
        'activeCount': 0,
        'inactiveCount': 1,
        'totalCount': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(catalogRef, <String, dynamic>{
        'version': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    try {
      await synchronizeInitialAdmins();
    } catch (error) {
      throw StateError('COMPANY_CLOSED_SYNC_PENDING:$error');
    }
  }

  Future<void> synchronizeInitialAdmins({
    void Function(String message)? onProgress,
  }) async {
    await requireDeveloper(
      source: 'initial_admin_access_sync',
      forceAccountSelection: false,
    );
    final snapshot = await preview();
    if (snapshot.recoveryRequired > 0 || snapshot.reviewRequired > 0) {
      throw StateError('INITIAL_SETUP_SYNC_REVIEW_REQUIRED:'
          '${snapshot.recoveryRequired}:${snapshot.reviewRequired}');
    }
    final initialized = snapshot.companies
        .where((company) => company.healthy)
        .toList(growable: false);
    final targetIds = initialized.map((company) => company.id).toSet();
    final version = snapshot.catalogVersion;
    final jobRef = _firestore.collection('access_sync_jobs').doc('catalog_$version');
    final operationId = '${DateTime.now().microsecondsSinceEpoch}-$version';
    final oldJob = await jobRef.get(const GetOptions(source: Source.server));
    if (oldJob.exists && oldJob.data()?['catalogVersion'] != version) {
      throw StateError('ACCESS_SYNC_JOB_VERSION_CONFLICT');
    }
    final previouslyCompleted = (oldJob.data()?['completedCompanyIds']
        as List<dynamic>? ?? const <dynamic>[])
        .map((value) => value.toString()).toSet().intersection(targetIds);
    final verifiedCompleted = <String>{};
    for (final id in previouslyCompleted) {
      final accountId = initialAccountId(id);
      final verified = await Future.wait([
        _firestore.collection('user_accounts').doc(accountId)
            .get(const GetOptions(source: Source.server)),
        _firestore.collection('user_accounts_show').doc('$id-$id')
            .collection('users').doc(accountId)
            .get(const GetOptions(source: Source.server)),
      ]);
      if (verified.every((doc) => doc.exists &&
          doc.data()?['companyId'] == id &&
          doc.data()?['isInitialAdmin'] == true &&
          _matchesCatalog(doc.data(), snapshot))) {
        verifiedCompleted.add(id);
      }
    }
    final remaining = initialized.where((company) =>
        !verifiedCompleted.contains(company.id)).toList(growable: false);
    await _firestore.runTransaction((tx) async {
      final previous = await tx.get(jobRef);
      if (previous.exists && previous.data()?['catalogVersion'] != version) {
        throw StateError('ACCESS_SYNC_JOB_VERSION_CONFLICT');
      }
      final previousCompleted = (previous.data()?['completedCompanyIds']
          as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString()).toSet();
      if (previous.exists && !setEquals(previousCompleted.intersection(targetIds),
          previouslyCompleted)) {
        throw StateError('ACCESS_SYNC_JOB_CHANGED');
      }
      final pending = targetIds.difference(verifiedCompleted).toList()..sort();
      final orderedCompleted = verifiedCompleted.toList()..sort();
      tx.set(jobRef, <String, dynamic>{
        'catalogVersion': version,
        'status': pending.isEmpty ? 'completed' : 'running',
        'operationId': operationId,
        'totalCount': initialized.length,
        'completedCount': orderedCompleted.length,
        'completedCompanyIds': orderedCompleted,
        'pendingCompanyIds': pending,
        'failedCompanyIds': <String>[],
        if (!previous.exists) 'createdAt': FieldValue.serverTimestamp(),
        if (pending.isEmpty) 'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    String? activeCompany;
    try {
      for (final company in remaining) {
        activeCompany = company.id;
        final accountId = initialAccountId(company.id);
        final accountRef = _firestore.collection('user_accounts').doc(accountId);
        final displayRef = _firestore.collection('user_accounts_show')
            .doc('${company.id}-${company.id}')
            .collection('users').doc(accountId);
        final catalogRef = _firestore.doc('access_catalog/current');
        await _firestore.runTransaction((tx) async {
          final reads = await Future.wait([
            tx.get(catalogRef), tx.get(accountRef), tx.get(displayRef),
            tx.get(jobRef),
          ]);
          final actualVersion = reads[0].data()?['version'] is int
              ? reads[0].data()!['version'] as int : 0;
          if (actualVersion != version) {
            throw StateError('ACCESS_CATALOG_CHANGED');
          }
          if (!reads[1].exists || !reads[2].exists ||
              reads[1].data()?['isInitialAdmin'] != true ||
              reads[1].data()?['companyId'] != company.id ||
              reads[2].data()?['isInitialAdmin'] != true ||
              reads[2].data()?['companyId'] != company.id) {
            throw StateError('INITIAL_SETUP_SYNC_DOCUMENT_MISSING:${company.id}');
          }
          if (!reads[3].exists || reads[3].data()?['catalogVersion'] != version ||
              reads[3].data()?['operationId'] != operationId) {
            throw StateError('ACCESS_SYNC_JOB_CHANGED');
          }
          final completed = (reads[3].data()?['completedCompanyIds'] as List<dynamic>? ??
              const <dynamic>[]).map((value) => value.toString()).toSet();
          if (!_matchesCatalog(reads[1].data(), snapshot) ||
              !_matchesCatalog(reads[2].data(), snapshot)) {
            final changes = <String, dynamic>{
              'divisions': snapshot.divisions,
              'areas': snapshot.areas,
              'areaIds': snapshot.areaIds,
              'modes': allModes,
              'accessCatalogVersion': version,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            tx.update(accountRef, changes);
            tx.update(displayRef, changes);
          }
          completed.add(company.id);
          final pending = targetIds.difference(completed).toList()..sort();
          final orderedCompleted = completed.intersection(targetIds).toList()..sort();
          tx.update(jobRef, <String, dynamic>{
            'status': pending.isEmpty ? 'completed' : 'running',
            'completedCount': orderedCompleted.length,
            'completedCompanyIds': orderedCompleted,
            'pendingCompanyIds': pending,
            'failedCompanyIds': <String>[],
            'updatedAt': FieldValue.serverTimestamp(),
            if (pending.isEmpty) 'completedAt': FieldValue.serverTimestamp(),
          });
        });
        onProgress?.call('${company.id}: 접근 목록 동기화 검증 완료');
      }
    } catch (error) {
      try {
        await _firestore.runTransaction((tx) async {
          final job = await tx.get(jobRef);
          if (!job.exists || job.data()?['operationId'] != operationId) return;
          final completed = (job.data()?['completedCompanyIds'] as List<dynamic>? ??
              const <dynamic>[]).map((value) => value.toString()).toSet();
          final pending = targetIds.difference(completed).toList()..sort();
          tx.update(jobRef, <String, dynamic>{
            'status': 'failed',
            'completedCount': completed.intersection(targetIds).length,
            'pendingCompanyIds': pending,
            'failedCompanyIds': activeCompany == null
                ? <String>[] : <String>[activeCompany],
            'errorType': error.runtimeType.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (_) {}
      rethrow;
    }
  }

}
