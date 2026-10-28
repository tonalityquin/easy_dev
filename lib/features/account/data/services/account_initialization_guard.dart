import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

enum AccountInitializationState { uninitialized, initialized, inconsistent }

class AccountInitializationInspection {
  const AccountInitializationInspection({
    required this.companyId,
    required this.state,
    required this.code,
    this.syncPending = false,
  });

  final String companyId;
  final AccountInitializationState state;
  final String code;
  final bool syncPending;

  bool get isInitialized => state == AccountInitializationState.initialized;

  void requireConsistent() {
    if (state == AccountInitializationState.inconsistent) {
      throw StateError('$code:$companyId');
    }
  }
}

class AccountInitializationGuard {
  const AccountInitializationGuard._();

  static const List<String> accessModes = <String>[
    'single', 'double', 'triple', 'minor',
  ];

  static bool matchesAccessCatalog({
    required Map<String, dynamic>? account,
    required String companyId,
    required List<String> areaNames,
    required List<String> areaIds,
    required int catalogVersion,
  }) {
    return account != null &&
        account['accessCatalogVersion'] == catalogVersion &&
        sameStrings(account['divisions'], <String>[companyId]) &&
        sameStrings(account['areas'], areaNames) &&
        sameStrings(account['areaIds'], areaIds) &&
        sameStrings(account['modes'], accessModes);
  }

  static String initialCode(String companyId) {
    if (companyId == 'belivus') return '01090351868';
    final digest = sha256.convert(utf8.encode(companyId)).toString();
    return 'a${digest.substring(0, 9)}1';
  }

  static String initialAccountId(String companyId) =>
      '${initialCode(companyId)}-$companyId';

  static bool sameStrings(dynamic left, dynamic right) {
    if (left is! List || right is! List) return false;
    final a = left.map((value) => value.toString()).toList()..sort();
    final b = right.map((value) => value.toString()).toList()..sort();
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static bool validLimits(Map<String, dynamic> data) {
    final active = data['activeLimit'];
    final total = data['totalLimit'];
    return active is int && total is int && active >= 0 &&
        total >= 0 && active <= total && total <= (1 << 30);
  }

  static bool validCounts(Map<String, dynamic> data) {
    final active = data['activeCount'];
    final inactive = data['inactiveCount'];
    final total = data['totalCount'];
    return active is int && inactive is int && total is int &&
        active >= 0 && inactive >= 0 && total == active + inactive;
  }

  static Future<AccountInitializationInspection> inspect({
    required FirebaseFirestore firestore,
    required String companyId,
  }) async {
    final id = companyId.trim();
    if (id.isEmpty) throw StateError('INITIALIZATION_COMPANY_REQUIRED');
    AccountInitializationInspection fail(String code) =>
        AccountInitializationInspection(
          companyId: id,
          state: AccountInitializationState.inconsistent,
          code: code,
        );
    final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('divisions').doc(id)
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final divisionData = division.data();
    if (divisionData == null) throw StateError('INITIALIZATION_DIVISION_NOT_FOUND:$id');
    if (divisionData['lifecycleStatus'] == 'closed' ||
        divisionData['lifecycleStatus'] == 'closing' ||
        divisionData['accountWriteLocked'] == true) {
      throw StateError('INITIALIZATION_COMPANY_UNAVAILABLE:$id');
    }
    if (divisionData['companyId'] != null && divisionData['companyId'] != id) {
      return fail('INITIALIZATION_DIVISION_SCOPE_MISMATCH');
    }
    final areas = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('areas')
        .where('division', isEqualTo: id)
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final nameSet = <String>{};
    var headquartersCount = 0;
    var areaPolicyInvalid = false;
    final regionNames = <String>[];
    final regionIds = <String>[];
    for (final area in areas.docs) {
      final data = area.data();
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty || !nameSet.add(name)) {
        return fail('INITIALIZATION_AREA_STRUCTURE_INVALID');
      }
      if (!validLimits(data)) areaPolicyInvalid = true;
      if (data['isHeadquarter'] == true) {
        headquartersCount++;
        if (name != id || area.id != '$id-$id') {
          return fail('INITIALIZATION_HEADQUARTER_INVALID');
        }
      }
      if (name == id && area.id != '$id-$id') {
        return fail('INITIALIZATION_HEADQUARTER_INVALID');
      }
      regionNames.add(name);
      regionIds.add(area.id);
    }
    if (headquartersCount > 1 || (areas.docs.isNotEmpty && !nameSet.contains(id))) {
      return fail('INITIALIZATION_HEADQUARTER_REQUIRED');
    }
    final accountId = initialAccountId(id);
    final accountRef = firestore.collection('user_accounts').doc(accountId);
    final codeRef = firestore.collection('user_account_codes').doc(initialCode(id));
    final headRef = firestore.collection('user_accounts_show').doc('$id-$id');
    final viewRef = headRef.collection('users').doc(accountId);
    final account = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => accountRef.get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final code = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => codeRef.get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final view = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => viewRef.get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final headMeta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => headRef.get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final metas = <String, Map<String, dynamic>?>{};
    for (final name in regionNames) {
      final meta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('user_accounts_show')
          .doc('$id-$name').get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
      metas[name] = meta.data();
    }
    final allMissing = !account.exists && !code.exists && !view.exists &&
        !headMeta.exists && metas.values.every((meta) => meta == null);
    if (allMissing) {
      for (final name in <String>{...regionNames, id}) {
        final orphan = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('user_accounts_show')
            .doc('$id-$name').collection('users').limit(1)
            .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
        if (orphan.docs.isNotEmpty) {
          return fail('INITIALIZATION_ORPHAN_PROJECTION');
        }
      }
      return AccountInitializationInspection(
        companyId: id,
        state: AccountInitializationState.uninitialized,
        code: 'INITIALIZATION_NOT_STARTED',
      );
    }
    if (areas.docs.isEmpty) {
      return fail('INITIALIZATION_HEADQUARTER_REQUIRED');
    }
    if (areaPolicyInvalid) {
      return fail('INITIALIZATION_AREA_POLICY_INVALID');
    }
    final data = account.data();
    final codeData = code.data();
    final viewData = view.data();
    if (data == null || codeData == null || viewData == null ||
        divisionData['initialAdminAccountId'] != accountId ||
        data['companyId'] != id || data['isInitialAdmin'] != true ||
        data['accountGradeId'] != 'headquartersAdmin' ||
        data['codeNumber'] != initialCode(id) ||
        codeData['userId'] != accountId ||
        codeData['codeNumber'] != initialCode(id)) {
      return fail('INITIALIZATION_ADMIN_DOCUMENT_INCOMPLETE');
    }
    final headMetaData = metas[id];
    if (headMetaData == null || headMetaData['totalCount'] is! int ||
        (headMetaData['totalCount'] as int) < 1 ||
        (data['isActive'] == true &&
            (headMetaData['activeCount'] is! int ||
             (headMetaData['activeCount'] as int) < 1)) ||
        (data['isActive'] != true &&
            (headMetaData['inactiveCount'] is! int ||
             (headMetaData['inactiveCount'] as int) < 1))) {
      return fail('INITIALIZATION_HEADQUARTER_COUNT_INVALID');
    }
    for (final field in <String>[
      'companyId', 'accountGradeId', 'isInitialAdmin',
      'isActive', 'email',
    ]) {
      if (viewData[field] != data[field]) {
        return fail('INITIALIZATION_DISPLAY_MISMATCH');
      }
    }
    if (!sameStrings(viewData['areas'], data['areas']) ||
        !sameStrings(viewData['permissionKeys'], data['permissionKeys'])) {
      return fail('INITIALIZATION_DISPLAY_MISMATCH');
    }
    if (!regionNames.contains(data['currentArea']) ||
        !regionNames.contains(data['selectedArea'])) {
      return fail('INITIALIZATION_CURRENT_AREA_INVALID');
    }
    for (final area in areas.docs) {
      final areaData = area.data();
      final name = (areaData['name'] ?? '').toString().trim();
      final meta = metas[name];
      if (meta == null || meta['division'] != id || meta['area'] != name ||
          !validCounts(meta) || !validLimits(meta) ||
          meta['activeLimit'] != areaData['activeLimit'] ||
          meta['totalLimit'] != areaData['totalLimit']) {
        return fail('INITIALIZATION_REGION_META_INCOMPLETE');
      }
    }
    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    if (email.isNotEmpty) {
      final identity = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('login_identity_accounts')
          .doc(email).get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
      if (identity.data()?['accountId'] != accountId ||
          identity.data()?['companyId'] != id ||
          identity.data()?['enabled'] != true) {
        return fail('INITIALIZATION_IDENTITY_MISMATCH');
      }
    }
    final catalog = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.doc('access_catalog/current')
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final catalogValue = catalog.data()?['version'];
    final catalogVersion = catalogValue is int ? catalogValue : 0;
    final syncPending = !matchesAccessCatalog(
          account: data,
          companyId: id,
          areaNames: regionNames,
          areaIds: regionIds,
          catalogVersion: catalogVersion,
        ) ||
        !matchesAccessCatalog(
          account: viewData,
          companyId: id,
          areaNames: regionNames,
          areaIds: regionIds,
          catalogVersion: catalogVersion,
        );
    return AccountInitializationInspection(
      companyId: id,
      state: AccountInitializationState.initialized,
      code: 'INITIALIZATION_COMPLETE',
      syncPending: syncPending,
    );
  }

  static Future<bool> isInitializedFast({
    required FirebaseFirestore firestore,
    required String companyId,
  }) async {
    final id = companyId.trim();
    if (id.isEmpty) throw StateError('INITIALIZATION_COMPANY_REQUIRED');
    final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('divisions').doc(id)
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    if (!division.exists || division.data()?['lifecycleStatus'] == 'closed' ||
        division.data()?['lifecycleStatus'] == 'closing' ||
        division.data()?['accountWriteLocked'] == true) {
      throw StateError('INITIALIZATION_COMPANY_UNAVAILABLE:$id');
    }
    final accountId = initialAccountId(id);
    final account = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('user_accounts').doc(accountId)
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final code = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('user_account_codes')
        .doc(initialCode(id)).get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final headRef = firestore.collection('user_accounts_show').doc('$id-$id');
    final head = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => headRef.get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    final view = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => headRef.collection('users').doc(accountId)
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    if (!account.exists && !code.exists && !head.exists && !view.exists) {
      return false;
    }
    final area = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('areas').doc('$id-$id')
        .get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    if (!account.exists || !code.exists || !head.exists || !view.exists ||
        !area.exists || area.data()?['division'] != id ||
        area.data()?['name'] != id || !validLimits(area.data() ?? <String, dynamic>{}) ||
        division.data()?['initialAdminAccountId'] != accountId ||
        account.data()?['companyId'] != id ||
        account.data()?['isInitialAdmin'] != true ||
        code.data()?['userId'] != accountId ||
        !validCounts(head.data() ?? <String, dynamic>{}) ||
        view.data()?['companyId'] != id) {
      throw StateError('INITIALIZATION_INCONSISTENT:$id');
    }
    return true;
  }

  static Future<bool> inTransaction({
    required Transaction transaction,
    required FirebaseFirestore firestore,
    required String companyId,
  }) async {
    final id = companyId.trim();
    if (id.isEmpty) throw StateError('INITIALIZATION_COMPANY_REQUIRED');
    final division = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(firestore.collection('divisions').doc(id)), source: 'account_initialization_guard.get');
    final divisionData = division.data();
    if (divisionData == null) throw StateError('INITIALIZATION_DIVISION_NOT_FOUND:$id');
    if (divisionData['lifecycleStatus'] == 'closed' ||
        divisionData['lifecycleStatus'] == 'closing' ||
        divisionData['accountWriteLocked'] == true) {
      throw StateError('INITIALIZATION_COMPANY_UNAVAILABLE:$id');
    }
    final accountId = initialAccountId(id);
    final account = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(
        firestore.collection('user_accounts').doc(accountId)), source: 'account_initialization_guard.get');
    final code = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(
        firestore.collection('user_account_codes').doc(initialCode(id))), source: 'account_initialization_guard.get');
    final headRef = firestore.collection('user_accounts_show').doc('$id-$id');
    final head = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(headRef), source: 'account_initialization_guard.get');
    final view = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(headRef.collection('users').doc(accountId)), source: 'account_initialization_guard.get');
    if (!account.exists && !code.exists && !head.exists && !view.exists) {
      return false;
    }
    final area = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(firestore.collection('areas').doc('$id-$id')), source: 'account_initialization_guard.get');
    final data = account.data();
    final headData = head.data();
    final viewData = view.data();
    if (data == null || headData == null || viewData == null ||
        !area.exists || area.data()?['division'] != id ||
        area.data()?['name'] != id || !validLimits(area.data() ?? <String, dynamic>{}) ||
        divisionData['initialAdminAccountId'] != accountId ||
        data['companyId'] != id || data['isInitialAdmin'] != true ||
        data['accountGradeId'] != 'headquartersAdmin' ||
        code.data()?['userId'] != accountId ||
        headData['division'] != id || headData['area'] != id ||
        !validCounts(headData) ||
        viewData['companyId'] != id ||
        viewData['isInitialAdmin'] != true) {
      throw StateError('INITIALIZATION_INCONSISTENT:$id');
    }
    return true;
  }

  static Future<bool> isInitialized({
    required FirebaseFirestore firestore,
    required String companyId,
  }) async {
    final inspection = await inspect(
      firestore: firestore, companyId: companyId);
    inspection.requireConsistent();
    return inspection.isInitialized;
  }
}

class AreaAccountLimits {
  const AreaAccountLimits({required this.active, required this.total});
  final int active;
  final int total;
}

class AreaAccountLimitPolicy {
  const AreaAccountLimitPolicy._();

  static Future<DocumentReference<Map<String, dynamic>>> resolve({
    required FirebaseFirestore firestore,
    required String companyId,
    required String areaName,
  }) async {
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('areas')
        .where('division', isEqualTo: companyId)
        .where('name', isEqualTo: areaName)
        .limit(2).get(const GetOptions(source: Source.server)), source: 'account_initialization_guard.get');
    if (snapshot.docs.length != 1) {
      throw StateError('AREA_POLICY_DOCUMENT_NOT_UNIQUE:$companyId/$areaName');
    }
    return snapshot.docs.single.reference;
  }

  static Future<AreaAccountLimits> inTransaction({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> areaRef,
    required String companyId,
    required String areaName,
  }) async {
    final snap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(areaRef), source: 'account_initialization_guard.get');
    final data = snap.data();
    if (data == null || data['division'] != companyId || data['name'] != areaName) {
      throw StateError('AREA_POLICY_SCOPE_CHANGED:$companyId/$areaName');
    }
    final active = data['activeLimit'];
    final total = data['totalLimit'];
    if (active is! int || total is! int || active < 0 || total < 0 ||
        active > total || total > (1 << 30)) {
      throw StateError('ACCOUNT_LIMIT_NOT_CONFIGURED:$companyId/$areaName');
    }
    return AreaAccountLimits(active: active, total: total);
  }
}
