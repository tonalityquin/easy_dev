import '../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/auth/google_auth_session.dart';
import '../../../../app/utils/access_gate_diagnostics.dart';
import '../../../dev/application/developer_account_authorization.dart';
import '../../../dev/application/login_gate_paths.dart';
import '../../domain/models/account_permission_policy.dart';
import 'company_grade_policy_service.dart';
import 'account_initialization_guard.dart';

class BootstrapArea {
  const BootstrapArea({
    required this.id,
    required this.name,
    required this.englishName,
    required this.isHeadquarter,
    this.activeLimit,
    this.totalLimit,
    this.createOnBootstrap = false,
  });

  final String id;
  final String name;
  final String englishName;
  final bool isHeadquarter;
  final int? activeLimit;
  final int? totalLimit;
  final bool createOnBootstrap;
}

class BootstrapCompany {
  const BootstrapCompany({
    required this.id,
    required this.areaDocuments,
    required this.areaConfigVersion,
  });

  final String id;
  final List<BootstrapArea> areaDocuments;
  final int areaConfigVersion;

  List<String> get areas => areaDocuments.map((area) => area.name).toSet().toList()..sort();
  List<String> get areaIds => areaDocuments.map((area) => area.id).toSet().toList()..sort();

  BootstrapArea get headquarter {
    final official = areaDocuments.where((area) => area.isHeadquarter).toList();
    if (official.length == 1) {
      if (official.single.name != id || official.single.id != '$id-$id') {
        throw StateError('INITIAL_SETUP_HEADQUARTER_PATH_CONFLICT:$id');
      }
      return official.single;
    }
    if (official.length > 1) throw StateError('INITIAL_SETUP_HEADQUARTER_DUPLICATE:$id');
    final legacy = areaDocuments.where((area) => area.name == id && area.id == '$id-$id').toList();
    if (legacy.length == 1) return legacy.single;
    throw StateError('INITIAL_SETUP_HEADQUARTER_REQUIRED:$id');
  }
}

class InitialAccountCreationResult {
  const InitialAccountCreationResult({
    required this.completedCompanyIds,
    required this.failedCompanyIds,
    required this.pendingCompanyIds,
    required this.failureCode,
    required this.activeCount,
    required this.registrationPendingCount,
  });

  final List<String> completedCompanyIds;
  final List<String> failedCompanyIds;
  final List<String> pendingCompanyIds;
  final String? failureCode;
  final int activeCount;
  final int registrationPendingCount;

  bool get succeeded => failedCompanyIds.isEmpty && pendingCompanyIds.isEmpty;
}

class AreaLimitMigrationResult {
  const AreaLimitMigrationResult({
    required this.scannedCount,
    required this.migratedCount,
    required this.unchangedCount,
    required this.missingMetaCount,
    required this.unconfiguredCount,
  });

  final int scannedCount;
  final int migratedCount;
  final int unchangedCount;
  final int missingMetaCount;
  final int unconfiguredCount;
}

class BootstrapPreview {
  const BootstrapPreview({
    required this.companies,
    required this.divisions,
    required this.areas,
    required this.areaIds,
  });

  final List<BootstrapCompany> companies;
  final List<String> divisions;
  final List<String> areas;
  final List<String> areaIds;

  int get pending => companies.length;
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

  static const List<String> allModes = AccountInitializationGuard.accessModes;

  static final List<String> initialPermissions =
      AccountPermissionPolicy.keys.toList(growable: false);

  static bool _matchesCatalog(
    Map<String, dynamic>? data,
    BootstrapCompany company,
    int version,
  ) => AccountInitializationGuard.matchesAccessCatalog(
        account: data,
        companyId: company.id,
        areaNames: company.areas,
        areaIds: company.areaIds,
        catalogVersion: version,
      );

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> ensureGeneralGradePolicies(String companyId) async {
    final company = companyId.trim();
    if (company.isEmpty) throw StateError('GRADE_POLICY_COMPANY_REQUIRED');
    final entries = AccountPermissionPolicy.presets.entries.toList(growable: false);
    final refs = entries.map((entry) => _firestore
        .collection('company_grade_policies').doc(company)
        .collection('grades').doc(entry.key)).toList(growable: false);
    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final snapshots = await Future.wait(refs.map(transaction.get));
      for (var index = 0; index < refs.length; index++) {
        if (snapshots[index].exists) {
          CompanyGradePolicyService.parse(
            companyId: company,
            gradeId: entries[index].key,
            data: snapshots[index].data(),
          );
          continue;
        }
        final entry = entries[index];
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(refs[index], <String, dynamic>{
          'companyId': company,
          'gradeId': entry.key,
          'name': AccountPermissionPolicy.gradeLabel(entry.key),
          'permissionKeys': entry.value.toList(growable: false)..sort(),
          'enabled': true,
          'version': 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }
    }), source: 'company_bootstrap_service.runTransaction');
  }

  static String initialCode(String companyId) =>
      AccountInitializationGuard.initialCode(companyId);

  static String initialAccountId(String companyId) =>
      AccountInitializationGuard.initialAccountId(companyId);

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
    late final DocumentSnapshot<Map<String, dynamic>> gate;
    try {
      gate = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => FirebaseFirestore.instance
          .doc(LoginGatePaths.developer)
          .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    } on FirebaseException catch (error) {
      AccessGateDiagnostics.record(
        'developer_auth_failed',
        source: source,
        reason: error.code,
      );
      rethrow;
    }
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
      FirebaseActivityMonitor.track(
        FirebaseActivityKind.read,
        () => _firestore.collection('divisions')
            .get(const GetOptions(source: Source.server)),
        source: 'bootstrap.divisions.preview',
      ),
      FirebaseActivityMonitor.track(
        FirebaseActivityKind.read,
        () => _firestore.collection('areas')
            .get(const GetOptions(source: Source.server)),
        source: 'bootstrap.areas.preview',
      ),
    ]);
    final companyDocs = snapshots[0].docs.where((doc) {
      final data = doc.data();
      return data['lifecycleStatus'] != 'closed' &&
          data['lifecycleStatus'] != 'closing' &&
          data['accountWriteLocked'] != true &&
          doc.id.trim().isNotEmpty;
    }).toList(growable: false);
    final companyIds = companyDocs.map((doc) => doc.id.trim()).toSet();
    final configVersions = <String, int>{
      for (final doc in companyDocs)
        doc.id: doc.data()['areaConfigVersion'] is int
            ? doc.data()['areaConfigVersion'] as int : 0,
    };
    final areaDocs = snapshots[1].docs.where((doc) =>
        companyIds.contains((doc.data()['division'] ?? '').toString().trim()))
        .toList(growable: false);
    final divisions = companyIds.toList()..sort();
    final companies = divisions.map((company) {
      final related = areaDocs.where((doc) =>
          (doc.data()['division'] ?? '').toString().trim() == company);
      final documents = related.map((doc) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString().trim();
        return BootstrapArea(
          id: doc.id,
          name: name,
          englishName: (data['englishName'] ?? '').toString().trim(),
          isHeadquarter: data['isHeadquarter'] == true,
          activeLimit: data['activeLimit'] is int ? data['activeLimit'] as int : null,
          totalLimit: data['totalLimit'] is int ? data['totalLimit'] as int : null,
        );
      }).where((area) => area.name.isNotEmpty).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (documents.length != related.length ||
          documents.map((area) => area.name).toSet().length != documents.length) {
        throw StateError('INITIAL_SETUP_AREA_INVALID:$company');
      }
      if (documents.isEmpty) {
        final division = companyDocs.firstWhere((doc) => doc.id == company).data();
        final englishName = (division['headquarterEnglishName'] ?? company).toString().trim();
        documents.add(BootstrapArea(
          id: '$company-$company',
          name: company,
          englishName: englishName.isEmpty ? company : englishName,
          isHeadquarter: true,
          activeLimit: 5,
          totalLimit: 10,
          createOnBootstrap: true,
        ));
      }
      for (final area in documents) {
        final active = area.activeLimit;
        final total = area.totalLimit;
        if (active == null || total == null) {
          throw StateError('INITIAL_SETUP_AREA_LIMIT_REQUIRED:$company/${area.name}');
        }
        if (active < 0 || total < 0 || active > total ||
            active > (1 << 30) || total > (1 << 30)) {
          throw StateError('INITIAL_SETUP_AREA_LIMIT_INVALID:$company/${area.name}');
        }
      }
      final result = BootstrapCompany(
        id: company,
        areaDocuments: documents,
        areaConfigVersion: configVersions[company] ?? 0,
      );
      final headquarters = result.headquarter;
      final activeAdmin = company == 'belivus';
      if (headquarters.totalLimit! < 1 ||
          (activeAdmin && headquarters.activeLimit! < 1)) {
        throw StateError('INITIAL_SETUP_HEADQUARTER_LIMIT_INSUFFICIENT:$company');
      }
      return result;
    }).toList(growable: false);
    final areas = companies.expand((company) => company.areas).toSet().toList()..sort();
    final areaIds = companies.expand((company) => company.areaIds).toSet().toList()..sort();
    return BootstrapPreview(
      companies: companies,
      divisions: divisions,
      areas: areas,
      areaIds: areaIds,
    );
  }

  Future<AreaLimitMigrationResult> migrateLegacyAreaLimits({
    void Function(String message)? onProgress,
  }) async {
    await requireDeveloper(
      source: 'area_limit_migration',
      forceAccountSelection: false,
    );
    final areaDocs = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('areas')
        .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    final ordered = areaDocs.docs.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final staged = <({
      DocumentReference<Map<String, dynamic>> areaRef,
      DocumentReference<Map<String, dynamic>> metaRef,
      String company,
      String name,
      Map<String, dynamic> updates,
    })>[];
    var unchanged = 0;
    var missingMeta = 0;
    var unconfigured = 0;
    for (final document in ordered) {
      final area = document.data();
      final company = (area['division'] ?? '').toString().trim();
      final name = (area['name'] ?? '').toString().trim();
      if (company.isEmpty || name.isEmpty ||
          document.id != '$company-$name') {
        throw StateError('AREA_LIMIT_MIGRATION_INVALID_AREA:${document.id}');
      }
      final metaRef = _firestore.collection('user_accounts_show')
          .doc('$company-$name');
      final metaSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => metaRef.get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
      final meta = metaSnap.data();
      if (meta == null) {
        missingMeta++;
      } else if (meta['division'] != company || meta['area'] != name) {
        throw StateError('AREA_LIMIT_MIGRATION_META_MISMATCH:$company/$name');
      }
      final updates = <String, dynamic>{};
      for (final field in <String>['activeLimit', 'totalLimit']) {
        final current = area[field];
        final old = meta?[field];
        if (current != null && (current is! int || current < 0 || current > (1 << 30)) ||
            old != null && (old is! int || old < 0 || old > (1 << 30))) {
          throw StateError('AREA_LIMIT_MIGRATION_INVALID_LIMIT:$company/$name/$field');
        }
        if (current != null && old != null && current != old) {
          throw StateError('AREA_LIMIT_MIGRATION_LIMIT_CONFLICT:$company/$name/$field');
        }
        if (current == null && old is int) updates[field] = old;
      }
      final active = updates['activeLimit'] ?? area['activeLimit'];
      final total = updates['totalLimit'] ?? area['totalLimit'];
      if (active is int && total is int && active > total) {
        throw StateError('AREA_LIMIT_MIGRATION_INVALID_RANGE:$company/$name');
      }
      if (active == null || total == null) unconfigured++;
      if (updates.isEmpty) {
        unchanged++;
      } else {
        staged.add((areaRef: document.reference, metaRef: metaRef,
          company: company, name: name, updates: updates));
      }
      onProgress?.call('지역 제한값 사전 검사 $company/$name');
    }
    for (final item in staged) {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final areaSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(item.areaRef), source: 'company_bootstrap_service.get');
        final metaSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(item.metaRef), source: 'company_bootstrap_service.get');
        final area = areaSnap.data();
        final meta = metaSnap.data();
        if (area == null || area['division'] != item.company ||
            area['name'] != item.name || meta == null ||
            meta['division'] != item.company || meta['area'] != item.name) {
          throw StateError('AREA_LIMIT_MIGRATION_SOURCE_CHANGED:${item.company}/${item.name}');
        }
        for (final field in item.updates.keys) {
          if (area[field] != null || meta[field] != item.updates[field]) {
            throw StateError('AREA_LIMIT_MIGRATION_SOURCE_CHANGED:${item.company}/${item.name}');
          }
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(item.areaRef, <String, dynamic>{
          ...item.updates,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }), source: 'company_bootstrap_service.runTransaction');
      onProgress?.call('지역 제한값 이관 완료 ${item.company}/${item.name}');
    }
    final checked = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('areas')
        .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    if (checked.docs.length != ordered.length) {
      throw StateError('AREA_LIMIT_MIGRATION_AREA_COUNT_CHANGED');
    }
    final byId = <String, Map<String, dynamic>>{
      for (final doc in checked.docs) doc.id: doc.data(),
    };
    for (final item in staged) {
      final data = byId[item.areaRef.id];
      if (data == null || item.updates.keys.any((field) =>
          data[field] != item.updates[field])) {
        throw StateError('AREA_LIMIT_MIGRATION_VERIFY_FAILED:${item.company}/${item.name}');
      }
    }
    return AreaLimitMigrationResult(
      scannedCount: ordered.length,
      migratedCount: staged.length,
      unchangedCount: unchanged,
      missingMetaCount: missingMeta,
      unconfiguredCount: unconfigured,
    );
  }

  Future<int> _readCatalogVersion() async {
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.doc('access_catalog/current')
        .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    final value = snapshot.data()?['version'];
    return value is int ? value : 0;
  }

  Future<BootstrapSyncProgress?> syncProgress(int version) async {
    final document = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('access_sync_jobs')
        .doc('catalog_$version')
        .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
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
    required String currentArea,
    required String englishCurrentArea,
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
      'currentArea': currentArea,
      'selectedArea': currentArea,
      'englishSelectedAreaName': englishCurrentArea,
      'isInitialAdmin': true,
      'accountGradeId': 'headquartersAdmin',
      'permissionKeys': initialPermissions,
      'permissionSchemaVersion': 2,
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
    required List<BootstrapArea> regionAreas,
    int? expectedAreaConfigVersion,
    Map<String, dynamic>? divisionData,
    Map<String, dynamic>? areaData,
    Map<String, dynamic>? metaData,
  }) async {
    final accountId = initialAccountId(company);
    final code = initialCode(company);
    final userRef = _firestore.collection('user_accounts').doc(accountId);
    final codeRef = _firestore.collection('user_account_codes').doc(code);
    final metaRef = _firestore.collection('user_accounts_show')
        .doc('$company-$company');
    final showRef = metaRef.collection('users').doc(accountId);
    final divisionRef = _firestore.collection('divisions').doc(company);
    final areaRef = _firestore.collection('areas').doc('$company-$company');
    final gradeRefs = AccountPermissionPolicy.presets.keys.map((gradeId) =>
        _firestore.collection('company_grade_policies').doc(company)
            .collection('grades').doc(gradeId)).toList(growable: false);
    final secondaryAreas = regionAreas.where((area) => area.name != company).toList();
    final regionRefs = secondaryAreas.map((area) =>
        _firestore.collection('user_accounts_show').doc('$company-${area.name}')).toList();
    final divisionSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'company_bootstrap_service.get');
    final areaSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(areaRef), source: 'company_bootstrap_service.get');
    final userSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(userRef), source: 'company_bootstrap_service.get');
    final codeSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(codeRef), source: 'company_bootstrap_service.get');
    final metaSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(metaRef), source: 'company_bootstrap_service.get');
    final displaySnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showRef), source: 'company_bootstrap_service.get');
    final regionSnapshots = await Future.wait(regionRefs.map(tx.get));
    final catalogSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(
        _firestore.doc('access_catalog/current')), source: 'company_bootstrap_service.get');
    final gradeSnapshots = await Future.wait(gradeRefs.map(tx.get));
    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    final identityRef = email.isEmpty ? null :
        _firestore.collection('login_identity_accounts').doc(email);
    final identitySnapshot = identityRef == null ? null :
        await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(identityRef), source: 'company_bootstrap_service.get');
    if (userSnapshot.exists || codeSnapshot.exists ||
        metaSnapshot.exists || displaySnapshot.exists ||
        regionSnapshots.any((snapshot) => snapshot.exists)) {
      throw StateError('INITIAL_SETUP_DOCUMENT_CONFLICT:$company');
    }
    if (identitySnapshot != null && identitySnapshot.exists &&
        (identitySnapshot.data()?['accountId'] != accountId ||
         identitySnapshot.data()?['companyId'] != company ||
         identitySnapshot.data()?['email'] != email)) {
      throw StateError('INITIAL_IDENTITY_ALREADY_RESERVED:$company');
    }
    final catalogValue = catalogSnapshot.data()?['version'];
    final actualVersion = catalogValue is int ? catalogValue : 0;
    if (actualVersion != expectedCatalogVersion) {
      throw StateError('ACCESS_CATALOG_CHANGED');
    }
    final plannedHeadquarters = regionAreas.where((area) => area.createOnBootstrap).toList();
    if (createCompany) {
      if (divisionSnapshot.exists || areaSnapshot.exists) {
        throw StateError('INITIAL_SETUP_COMPANY_ALREADY_EXISTS');
      }
    } else {
      final divisionData = divisionSnapshot.data();
      if (divisionData == null ||
          divisionData['lifecycleStatus'] == 'closed' ||
          divisionData['lifecycleStatus'] == 'closing' ||
          divisionData['accountWriteLocked'] == true) {
        throw StateError('INITIAL_SETUP_COMPANY_NOT_WRITABLE:$company');
      }
      final actualAreaVersion = divisionData['areaConfigVersion'] is int
          ? divisionData['areaConfigVersion'] as int : 0;
      if (expectedAreaConfigVersion == null ||
          actualAreaVersion != expectedAreaConfigVersion) {
        throw StateError('AREA_CONFIGURATION_CHANGED:$company');
      }
      final storedCompany = (divisionData['companyId'] ?? '')
          .toString().trim();
      if (storedCompany.isNotEmpty && storedCompany != company) {
        throw StateError('INITIAL_SETUP_COMPANY_ID_CONFLICT:$company');
      }
      if (plannedHeadquarters.length > 1 ||
          (plannedHeadquarters.isNotEmpty && areaSnapshot.exists) ||
          (plannedHeadquarters.isEmpty && !areaSnapshot.exists)) {
        throw StateError('INITIAL_SETUP_HEADQUARTER_STATE_CHANGED:$company');
      }
      if (plannedHeadquarters.isEmpty) {
        final existingHead = areaSnapshot.data();
        final expectedHead = regionAreas.where((area) => area.name == company).toList();
        if (existingHead == null || expectedHead.length != 1 ||
            existingHead['division'] != company ||
            existingHead['name'] != company ||
            existingHead['activeLimit'] != expectedHead.single.activeLimit ||
            existingHead['totalLimit'] != expectedHead.single.totalLimit) {
          throw StateError('INITIAL_SETUP_HEADQUARTER_POLICY_CHANGED:$company');
        }
      }
    }
    for (var index = 0; index < gradeRefs.length; index++) {
      if (gradeSnapshots[index].exists) continue;
      final gradeId = gradeRefs[index].id;
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(gradeRefs[index], <String, dynamic>{
        'companyId': company,
        'gradeId': gradeId,
        'name': AccountPermissionPolicy.gradeLabel(gradeId),
        'permissionKeys': AccountPermissionPolicy.presetPermissions(gradeId)
            .toList(growable: false),
        'enabled': true,
        'version': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }));
    }
    if (identityRef != null) {
      if (identitySnapshot?.exists == true) {
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(identityRef, <String, dynamic>{
          'enabled': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      } else {
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(identityRef, <String, dynamic>{
          'accountId': accountId,
          'companyId': company,
          'email': email,
          'enabled': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }
    }
    if (createCompany) {
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(divisionRef, <String, dynamic>{
        ...divisionData!,
        'companyId': company,
        'initialAdminAccountId': accountId,
        'lifecycleStatus': 'active',
        'accountWriteLocked': false,
        'areaConfigVersion': 1,
      }));
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(areaRef, areaData!));
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(_firestore.doc('access_catalog/current'), <String, dynamic>{
        'version': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } else {
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
        'companyId': company,
        'initialAdminAccountId': accountId,
        'accountWriteVersion': FieldValue.increment(1),
        if (plannedHeadquarters.isNotEmpty)
          'areaConfigVersion': FieldValue.increment(1),
      }));
      if (plannedHeadquarters.isNotEmpty) {
        final headquarter = plannedHeadquarters.single;
        final division = divisionSnapshot.data() ?? <String, dynamic>{};
        final storedCapabilities = division['headquarterCapabilities'];
        final capabilities = storedCapabilities is List
            ? storedCapabilities.whereType<String>().toList(growable: false)
            : <String>[];
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(areaRef, <String, dynamic>{
          'name': company,
          'englishName': headquarter.englishName,
          'division': company,
          'modes': allModes,
          'capabilities': capabilities,
          'isHeadquarter': true,
          'activeLimit': 5,
          'totalLimit': 10,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(_firestore.doc('access_catalog/current'), <String, dynamic>{
          'version': expectedCatalogVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)));
      }
    }
    FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(userRef, data));
    FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(codeRef, <String, dynamic>{
      'userId': accountId,
      'codeNumber': code,
      'area': company,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
    final active = data['isActive'] == true ? 1 : 0;
    final headquarters = regionAreas.where((area) => area.name == company).toList();
    FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(metaRef, <String, dynamic>{
      ...?metaData,
      if (headquarters.isNotEmpty && headquarters.first.activeLimit != null)
        'activeLimit': headquarters.first.activeLimit,
      if (headquarters.isNotEmpty && headquarters.first.totalLimit != null)
        'totalLimit': headquarters.first.totalLimit,
      'division': company,
      'area': company,
      'activeCount': active,
      'inactiveCount': 1 - active,
      'totalCount': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }));
    for (var index = 0; index < regionRefs.length; index++) {
      final area = secondaryAreas[index];
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(regionRefs[index], <String, dynamic>{
        'division': company,
        'area': area.name,
        'activeCount': 0,
        'inactiveCount': 0,
        'totalCount': 0,
        if (area.activeLimit != null) 'activeLimit': area.activeLimit,
        if (area.totalLimit != null) 'totalLimit': area.totalLimit,
        'updatedAt': FieldValue.serverTimestamp(),
      }));
    }
    final showData = Map<String, dynamic>.from(data)
      ..remove('passwordHash')
      ..remove('passwordSalt')
      ..remove('password');
    FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(showRef, showData));
  }

  Future<Map<String, AccountInitializationInspection>> inspectInitializations(
      BootstrapPreview preview) async {
    final inspections = <String, AccountInitializationInspection>{};
    for (final company in preview.companies) {
      inspections[company.id] = await AccountInitializationGuard.inspect(
        firestore: _firestore, companyId: company.id);
    }
    return inspections;
  }

  Future<Set<String>> completedInitializations(BootstrapPreview preview) async {
    final inspections = await inspectInitializations(preview);
    final completed = <String>{};
    for (final entry in inspections.entries) {
      entry.value.requireConsistent();
      if (entry.value.isInitialized) completed.add(entry.key);
    }
    return completed;
  }

  Future<InitialAccountCreationResult> initializeExisting({
    required BootstrapPreview preview,
    Set<String>? targetCompanyIds,
    String? belivusPassword,
    void Function(String message)? onProgress,
  }) async {
    await requireDeveloper(
      source: 'launcher_initial_setup_commit',
      forceAccountSelection: false,
    );
    final companies = targetCompanyIds == null
        ? preview.companies
        : preview.companies.where((company) =>
            targetCompanyIds.contains(company.id)).toList(growable: false);
    if (targetCompanyIds != null &&
        (targetCompanyIds.isEmpty || companies.length != targetCompanyIds.length)) {
      throw StateError('INITIAL_SETUP_RETRY_TARGET_CHANGED');
    }
    final completed = <String>[];
    final failed = <String>[];
    final pending = <String>[];
    String? failureCode;
    var activeCount = 0;
    var registrationPendingCount = 0;
    for (var index = 0; index < companies.length; index++) {
      final company = companies[index];
      try {
        final inspection = await AccountInitializationGuard.inspect(
          firestore: _firestore, companyId: company.id);
        inspection.requireConsistent();
        if (inspection.isInitialized) {
          completed.add(company.id);
          onProgress?.call('${company.id}: 이미 초기화가 완료되어 기존 문서를 유지합니다.');
          continue;
        }
        final headquarter = company.headquarter;
        final version = await _readCatalogVersion();
        final createsHeadquarter = headquarter.createOnBootstrap;
        final data = _accountData(
          company: company.id,
          divisions: <String>[company.id],
          areas: company.areas,
          areaIds: company.areaIds,
          currentArea: headquarter.name,
          englishCurrentArea: headquarter.englishName.isEmpty
              ? headquarter.name : headquarter.englishName,
          accessCatalogVersion: version + (createsHeadquarter ? 1 : 0),
          password: belivusPassword,
        );
        onProgress?.call(createsHeadquarter
            ? '${company.id}: 본사 지역과 최초 관리자 문서를 함께 기록합니다.'
            : '${company.id}: 최초 관리자 문서를 기록합니다.');
        await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
          await _writeInitialAdmin(
            tx: tx,
            company: company.id,
            data: data,
            createCompany: false,
            expectedCatalogVersion: version,
            expectedAreaConfigVersion: company.areaConfigVersion,
            regionAreas: company.areaDocuments,
          );
        }), source: 'company_bootstrap_service.runTransaction');
        completed.add(company.id);
        if (data['isActive'] == true) {
          activeCount++;
        } else {
          registrationPendingCount++;
        }
        onProgress?.call('${company.id}: 초기 관리자 생성 완료');
        AccessGateDiagnostics.record(
          'bootstrap_created',
          source: 'launcher_initial_setup',
          group: 'developer',
        );
      } catch (error) {
        failed.add(company.id);
        final code = error is FirebaseException
            ? 'FIREBASE_${error.code.toUpperCase().replaceAll('-', '_')}'
            : error is StateError
                ? error.message.toString().split(':').first
                : error.runtimeType.toString();
        failureCode ??= code;
        onProgress?.call('${company.id}: 생성 실패 ($code)');
        if (error is FirebaseException &&
            (error.code == 'permission-denied' ||
             error.code == 'unavailable' ||
             error.code == 'unauthenticated') ||
            code == 'ACCESS_CATALOG_CHANGED' ||
            code == 'AREA_CONFIGURATION_CHANGED') {
          pending.addAll(companies.skip(index + 1).map((item) => item.id));
          break;
        }
      }
    }
    if (completed.isNotEmpty) {
      try {
        onProgress?.call('초기 관리자 접근 목록의 최신 카탈로그 버전을 동기화합니다.');
        await synchronizeInitialAdmins(onProgress: onProgress);
      } catch (error) {
        onProgress?.call('계정 생성은 유지됐으며 접근 목록 재동기화가 필요합니다: ${error.runtimeType}');
      }
    }
    return InitialAccountCreationResult(
      completedCompanyIds: List<String>.unmodifiable(completed),
      failedCompanyIds: List<String>.unmodifiable(failed),
      pendingCompanyIds: List<String>.unmodifiable(pending),
      failureCode: failureCode,
      activeCount: activeCount,
      registrationPendingCount: registrationPendingCount,
    );
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
    final inspection = await AccountInitializationGuard.inspect(
      firestore: _firestore, companyId: company);
    inspection.requireConsistent();
    if (!inspection.isInitialized) {
      throw StateError('ACCOUNT_INITIALIZATION_REQUIRED:$company');
    }
    final divisionRef = _firestore.collection('divisions').doc(company);
    final metaRef = _firestore.collection('user_accounts_show')
        .doc('$company-$company');
    final collection = metaRef.collection('users');
    final operationId = DateTime.now().microsecondsSinceEpoch.toString();
    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'company_bootstrap_service.get');
      final meta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(metaRef), source: 'company_bootstrap_service.get');
      if (!meta.exists) throw StateError('ACCOUNT_META_MISSING:$company');
      if (!division.exists || division.data()?['lifecycleStatus'] == 'closed' ||
          division.data()?['lifecycleStatus'] == 'closing' ||
          division.data()?['accountWriteLocked'] == true) {
        throw StateError('COMPANY_COUNT_REBUILD_UNAVAILABLE:$company');
      }
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
        'accountWriteLocked': true,
        'accountWriteLockId': operationId,
        'accountWriteVersion': FieldValue.increment(1),
      }));
    }), source: 'company_bootstrap_service.runTransaction');
    onProgress?.call('$company: 계정 집계 재구축 잠금 적용');
    try {
      final all = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => collection.get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
      final active = all.docs.where((doc) => doc.data()['isActive'] == true).length;
      final inactive = all.docs.length - active;
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'company_bootstrap_service.get');
        final meta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(metaRef), source: 'company_bootstrap_service.get');
        if (!meta.exists) throw StateError('ACCOUNT_META_MISSING:$company');
        if (division.data()?['accountWriteLockId'] != operationId ||
            division.data()?['accountWriteLocked'] != true ||
            division.data()?['lifecycleStatus'] == 'closed') {
          throw StateError('COMPANY_COUNT_REBUILD_LOCK_CHANGED:$company');
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(metaRef, <String, dynamic>{
          'activeCount': active,
          'inactiveCount': inactive,
          'totalCount': active + inactive,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
          'accountWriteLocked': false,
          'accountWriteLockId': FieldValue.delete(),
          'accountWriteVersion': FieldValue.increment(1),
        }));
      }), source: 'company_bootstrap_service.runTransaction');
      onProgress?.call('$company: 활성 $active · 비활성 $inactive 집계 재구축 완료');
    } catch (error) {
      try {
        await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
          final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'company_bootstrap_service.get');
          if (division.data()?['accountWriteLockId'] == operationId &&
              division.data()?['accountWriteLocked'] == true) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
              'accountWriteLocked': false,
              'accountWriteLockId': FieldValue.delete(),
            }));
          }
        }), source: 'company_bootstrap_service.runTransaction');
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
    final catalogVersion = await _readCatalogVersion();
    if (previous.divisions.contains(company)) {
      throw StateError('INITIAL_SETUP_COMPANY_ALREADY_EXISTS');
    }
    final requestedActive = areaData['activeLimit'];
    final requestedTotal = areaData['totalLimit'];
    if (requestedActive is! int || requestedTotal is! int ||
        requestedActive < 0 || requestedTotal < 1 ||
        requestedActive > requestedTotal || requestedTotal > (1 << 30) ||
        (company == 'belivus' && requestedActive < 1)) {
      throw StateError('INITIAL_SETUP_HEADQUARTER_LIMIT_INSUFFICIENT:$company');
    }
    final inspections = await inspectInitializations(previous);
    for (final inspection in inspections.values) {
      inspection.requireConsistent();
    }
    final initializedCount = inspections.values
        .where((inspection) => inspection.isInitialized).length;
    if (initializedCount > 0 && initializedCount != inspections.length) {
      throw StateError('INITIAL_SETUP_PARTIAL_PENDING');
    }
    if (initializedCount == 0) {
      final divisionRef = _firestore.collection('divisions').doc(company);
      final areaRef = _firestore.collection('areas').doc('$company-$company');
      final metaRef = _firestore.collection('user_accounts_show')
          .doc('$company-$company');
      final accountRef = _firestore.collection('user_accounts').doc(initialAccountId(company));
      final codeRef = _firestore.collection('user_account_codes').doc(initialCode(company));
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'company_bootstrap_service.get');
        final area = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(areaRef), source: 'company_bootstrap_service.get');
        final meta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(metaRef), source: 'company_bootstrap_service.get');
        final account = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(accountRef), source: 'company_bootstrap_service.get');
        final code = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(codeRef), source: 'company_bootstrap_service.get');
        if (division.exists || area.exists || meta.exists || account.exists || code.exists) {
          throw StateError('INITIAL_SETUP_COMPANY_ALREADY_EXISTS');
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.create, () => tx.set(divisionRef, <String, dynamic>{
          ...divisionData,
          'companyId': company,
          'initialAdminAccountId': '',
          'lifecycleStatus': 'active',
          'accountWriteLocked': false,
          'areaConfigVersion': 0,
          'headquarterEnglishName': (areaData['englishName'] ?? company).toString(),
          'headquarterCapabilities': areaData['capabilities'] is List
              ? List<dynamic>.from(areaData['capabilities'] as List)
              : <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }), source: 'company_bootstrap_service.runTransaction');
      return;
    }
    final headquarters = BootstrapArea(
      id: '$company-$company',
      name: company,
      englishName: (areaData['englishName'] ?? '').toString().trim(),
      isHeadquarter: true,
      activeLimit: areaData['activeLimit'] is int ? areaData['activeLimit'] as int : null,
      totalLimit: areaData['totalLimit'] is int ? areaData['totalLimit'] as int : null,
    );
    final total = headquarters.totalLimit;
    final active = headquarters.activeLimit;
    if (total == null || active == null || total < 1 ||
        active < 0 || active > total || total > (1 << 30) ||
        (company == 'belivus' && active < 1)) {
      throw StateError('INITIAL_SETUP_HEADQUARTER_LIMIT_INSUFFICIENT:$company');
    }
    final data = _accountData(
      company: company,
      divisions: <String>[company],
      areas: <String>[company],
      areaIds: <String>['$company-$company'],
      currentArea: headquarters.name,
      englishCurrentArea: headquarters.englishName.isEmpty
          ? headquarters.name : headquarters.englishName,
      accessCatalogVersion: catalogVersion + 1,
      password: belivusPassword,
    );
    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      await _writeInitialAdmin(
        tx: tx,
        company: company,
        data: data,
        createCompany: true,
        expectedCatalogVersion: catalogVersion,
        regionAreas: const <BootstrapArea>[],
        divisionData: divisionData,
        areaData: areaData,
        metaData: metaData,
      );
    }), source: 'company_bootstrap_service.runTransaction');
    await synchronizeInitialAdmins();
  }

  Future<void> closeCompany({required String company}) async {
    await requireDeveloper(
      source: 'close_company',
      forceAccountSelection: false,
    );
    final normalized = company.trim();
    if (normalized.isEmpty) throw StateError('COMPANY_ID_REQUIRED');
    final inspection = await AccountInitializationGuard.inspect(
      firestore: _firestore, companyId: normalized);
    inspection.requireConsistent();
    final divisionRef = _firestore.collection('divisions').doc(normalized);
    final accountId = initialAccountId(normalized);
    final accountRef = _firestore.collection('user_accounts').doc(accountId);
    final metaRef = _firestore.collection('user_accounts_show')
        .doc('$normalized-$normalized');
    final displayRef = metaRef.collection('users').doc(accountId);
    final catalogRef = _firestore.doc('access_catalog/current');
    final divisionBefore = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => divisionRef.get(
      const GetOptions(source: Source.server),
    ), source: 'company_bootstrap_service.get');
    if (!divisionBefore.exists ||
        divisionBefore.data()?['accountWriteLocked'] == true) {
      throw StateError('COMPANY_CLOSE_UNAVAILABLE:$normalized');
    }
    final versionValue = divisionBefore.data()?['accountWriteVersion'];
    final expectedWriteVersion = versionValue is int ? versionValue : 0;
    final dependentTablets = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('tablet_accounts')
        .where('companyId', isEqualTo: normalized).limit(1)
        .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    if (dependentTablets.docs.isNotEmpty) {
      throw StateError('COMPANY_CLOSE_RELATED_TABLET_EXISTS');
    }
    final dependentAccounts = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('user_accounts')
        .where('companyId', isEqualTo: normalized).limit(2)
        .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    if (dependentAccounts.docs.any((doc) => doc.id != accountId)) {
      throw StateError('COMPANY_CLOSE_RELATED_ACCOUNT_EXISTS');
    }
    final existingAdmin = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => accountRef.get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
    if (!existingAdmin.exists) {
      final codeRef = _firestore.collection('user_account_codes')
          .doc(initialCode(normalized));
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'company_bootstrap_service.get');
        final admin = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(accountRef), source: 'company_bootstrap_service.get');
        final code = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(codeRef), source: 'company_bootstrap_service.get');
        final meta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(metaRef), source: 'company_bootstrap_service.get');
        final view = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(displayRef), source: 'company_bootstrap_service.get');
        if (division.data()?['lifecycleStatus'] == 'closed' ||
            division.data()?['accountWriteLocked'] == true ||
            admin.exists || code.exists || meta.exists || view.exists) {
          throw StateError('COMPANY_CLOSE_INTEGRITY_REVIEW_REQUIRED');
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
          'lifecycleStatus': 'closed',
          'closedAt': FieldValue.serverTimestamp(),
        }));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(catalogRef, <String, dynamic>{
          'version': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)));
      }), source: 'company_bootstrap_service.runTransaction');
      await synchronizeInitialAdmins();
      return;
    }
    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final reads = await Future.wait([
        tx.get(divisionRef),
        tx.get(accountRef),
        tx.get(displayRef),
        tx.get(metaRef),
        tx.get(catalogRef),
      ]);
      final division = reads[0].data();
      final account = reads[1].data();
      final meta = reads[3].data();
      final writeVersion = division?['accountWriteVersion'];
      final currentWriteVersion = writeVersion is int ? writeVersion : 0;
      if (division == null || division['lifecycleStatus'] == 'closed' ||
          division['accountWriteLocked'] == true ||
          currentWriteVersion != expectedWriteVersion) {
        throw StateError('COMPANY_ALREADY_CLOSED_OR_MISSING');
      }
      if (division['initialAdminAccountId'] != accountId ||
          account == null || account['companyId'] != normalized ||
          account['isInitialAdmin'] != true ||
          !reads[2].exists || meta == null || meta['totalCount'] != 1) {
        throw StateError('COMPANY_CLOSE_INTEGRITY_REVIEW_REQUIRED');
      }
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
        'lifecycleStatus': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      }));
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(accountRef, <String, dynamic>{
        'isActive': false,
        'accountStatus': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      }));
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(displayRef, <String, dynamic>{
        'isActive': false,
        'accountStatus': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      }));
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(metaRef, <String, dynamic>{
        'activeCount': 0,
        'inactiveCount': 1,
        'totalCount': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }));
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(catalogRef, <String, dynamic>{
        'version': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    }), source: 'company_bootstrap_service.runTransaction');
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
    final initialized = <BootstrapCompany>[];
    for (final company in snapshot.companies) {
      final account = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('user_accounts')
          .doc(initialAccountId(company.id))
          .get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
      if (account.exists &&
          account.data()?['companyId'] == company.id &&
          account.data()?['isInitialAdmin'] == true) {
        initialized.add(company);
      }
    }
    final targetIds = initialized.map((company) => company.id).toSet();
    final version = await _readCatalogVersion();
    final jobRef = _firestore.collection('access_sync_jobs').doc('catalog_$version');
    final operationId = '${DateTime.now().microsecondsSinceEpoch}-$version';
    final oldJob = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => jobRef.get(const GetOptions(source: Source.server)), source: 'company_bootstrap_service.get');
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
        FirebaseActivityMonitor.track(
          FirebaseActivityKind.read,
          () => _firestore.collection('user_accounts').doc(accountId)
              .get(const GetOptions(source: Source.server)),
          source: 'bootstrap.account.verify',
        ),
        FirebaseActivityMonitor.track(
          FirebaseActivityKind.read,
          () => _firestore.collection('user_accounts_show').doc('$id-$id')
              .collection('users').doc(accountId)
              .get(const GetOptions(source: Source.server)),
          source: 'bootstrap.display.verify',
        ),
      ]);
      if (verified.every((doc) => doc.exists &&
          doc.data()?['companyId'] == id &&
          doc.data()?['isInitialAdmin'] == true &&
          _matchesCatalog(doc.data(), initialized.firstWhere((company) => company.id == id), version))) {
        verifiedCompleted.add(id);
      }
    }
    final remaining = initialized.where((company) =>
        !verifiedCompleted.contains(company.id)).toList(growable: false);
    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final previous = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(jobRef), source: 'company_bootstrap_service.get');
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
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(jobRef, <String, dynamic>{
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
      }, SetOptions(merge: true)));
    }), source: 'company_bootstrap_service.runTransaction');
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
        await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
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
          if (!_matchesCatalog(reads[1].data(), company, version) ||
              !_matchesCatalog(reads[2].data(), company, version)) {
            final changes = <String, dynamic>{
              'divisions': <String>[company.id],
              'areas': company.areas,
              'areaIds': company.areaIds,
              'modes': allModes,
              'accessCatalogVersion': version,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(accountRef, changes));
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(displayRef, changes));
          }
          completed.add(company.id);
          final pending = targetIds.difference(completed).toList()..sort();
          final orderedCompleted = completed.intersection(targetIds).toList()..sort();
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(jobRef, <String, dynamic>{
            'status': pending.isEmpty ? 'completed' : 'running',
            'completedCount': orderedCompleted.length,
            'completedCompanyIds': orderedCompleted,
            'pendingCompanyIds': pending,
            'failedCompanyIds': <String>[],
            'updatedAt': FieldValue.serverTimestamp(),
            if (pending.isEmpty) 'completedAt': FieldValue.serverTimestamp(),
          }));
        }), source: 'company_bootstrap_service.runTransaction');
        onProgress?.call('${company.id}: 접근 목록 동기화 검증 완료');
      }
    } catch (error) {
      try {
        await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
          final job = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(jobRef), source: 'company_bootstrap_service.get');
          if (!job.exists || job.data()?['operationId'] != operationId) return;
          final completed = (job.data()?['completedCompanyIds'] as List<dynamic>? ??
              const <dynamic>[]).map((value) => value.toString()).toSet();
          final pending = targetIds.difference(completed).toList()..sort();
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(jobRef, <String, dynamic>{
            'status': 'failed',
            'completedCount': completed.intersection(targetIds).length,
            'pendingCompanyIds': pending,
            'failedCompanyIds': activeCompany == null
                ? <String>[] : <String>[activeCompany],
            'errorType': error.runtimeType.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          }));
        }), source: 'company_bootstrap_service.runTransaction');
      } catch (_) {}
      rethrow;
    }
  }

}
