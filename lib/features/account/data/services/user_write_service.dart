import '../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../dev/application/developer_account_authorization.dart';
import '../../../../shared/auth/account_code_number.dart';
import '../../applications/tablet_account_diagnostics.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';
import 'company_grade_policy_service.dart';
import 'account_initialization_guard.dart';

class _ShowAccountCounts {
  const _ShowAccountCounts({
    required this.activeCount,
    required this.inactiveCount,
  });

  final int activeCount;
  final int inactiveCount;

  int get totalCount => activeCount + inactiveCount;

  _ShowAccountCounts applyDeltas({
    int activeDelta = 0,
    int inactiveDelta = 0,
  }) {
    var active = activeCount + activeDelta;
    var inactive = inactiveCount + inactiveDelta;
    if (active < 0) active = 0;
    if (inactive < 0) inactive = 0;
    return _ShowAccountCounts(activeCount: active, inactiveCount: inactive);
  }

  Map<String, int> toMap() {
    return <String, int>{
      'activeCount': activeCount,
      'inactiveCount': inactiveCount,
      'totalCount': totalCount,
    };
  }
}

class UserWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getUserShowCollectionRef() {
    return _firestore.collection('user_accounts_show');
  }

  CollectionReference<Map<String, dynamic>> _getUserCodeCollectionRef() {
    return _firestore.collection('user_account_codes');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }


  String _tabletAreaOf(TabletModel tablet) {
    final selected = (tablet.selectedArea ?? '').trim();
    if (selected.isNotEmpty) return selected;
    final current = (tablet.currentArea ?? '').trim();
    if (current.isNotEmpty) return current;
    if (tablet.areas.isNotEmpty) {
      final first = tablet.areas.first.trim();
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  String _canonicalTabletDocumentId(TabletModel tablet) {
    return AccountCodeNumber.documentId(
      codeNumber: tablet.codeNumber,
      area: _tabletAreaOf(tablet),
    );
  }

  void _assertCanonicalTabletDocumentId(TabletModel tablet) {
    final expected = _canonicalTabletDocumentId(tablet);
    if (expected.isEmpty) {
      throw StateError('태블릿 문서 ID를 만들 코드번호 또는 업무 지역 정보가 없습니다.');
    }
    if (tablet.id.trim() != expected) {
      throw StateError('태블릿 문서 ID가 코드번호-업무지역명 규칙과 일치하지 않습니다.');
    }
  }

  Future<void> _assertUniqueTabletCodeNumber(
    String codeNumber, {
    String? excludeDocumentId,
    bool allowLegacyNumeric = false,
  }) async {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    final valid = allowLegacyNumeric
        ? AccountCodeNumber.isValid(normalized)
        : AccountCodeNumber.isGeneratedCode(normalized);
    if (!valid) {
      throw StateError(
        allowLegacyNumeric
            ? '태블릿 코드번호가 로그인 호환 규칙과 일치하지 않습니다.'
            : '태블릿 코드번호가 11자리 영문·숫자 조합 규칙과 일치하지 않습니다.',
      );
    }

    final legacyNumeric = RegExp(r'^\d{10,11}$').hasMatch(normalized);
    final fields = <String>[
      'codeNumber',
      if (allowLegacyNumeric && legacyNumeric) 'phone',
      if (allowLegacyNumeric && legacyNumeric) 'handle',
    ];
    final snapshots = await Future.wait(
      fields.map(
        (field) => FirebaseActivityMonitor.track(
            FirebaseActivityKind.read,
            () => _getTabletCollectionRef()
                .where(field, isEqualTo: normalized)
                .limit(10)
                .get(),
            source: 'tablet.account.code_lookup',
          ),
      ),
    );
    final excluded = (excludeDocumentId ?? '').trim();
    final duplicated = snapshots
        .expand((snapshot) => snapshot.docs)
        .any((doc) => doc.id != excluded);
    if (duplicated) {
      throw StateError('해당 코드번호로 등록된 태블릿 계정이 이미 있습니다.');
    }
  }

  String _inferAreaFromHyphenId(String id) {
    final idx = id.lastIndexOf('-');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }

  String _showDocId(String? division, String? area) {
    final d = (division ?? '').trim().isEmpty ? 'unknownDivision' : (division ?? '').trim();
    final a = (area ?? '').trim().isEmpty ? 'unknownArea' : (area ?? '').trim();
    return '$d-$a';
  }

  String _divisionOfUser(UserModel u) {
    final company = u.companyId.trim();
    if (company.isEmpty) throw StateError('ACCOUNT_COMPANY_ID_REQUIRED');
    return company;
  }

  String _areaOfUser(UserModel u) {
    final ca = (u.currentArea ?? '').trim();
    if (ca.isNotEmpty) return ca;

    final sa = (u.selectedArea ?? '').trim();
    if (sa.isNotEmpty) return sa;

    final a0 = (u.areas.isNotEmpty ? u.areas.first : '').trim();
    if (a0.isNotEmpty) return a0;

    return _inferAreaFromHyphenId(u.id);
  }

  Map<String, dynamic> _toUserAccountsMap(
    UserModel user, {
    bool? isActive,
  }) {
    final map = Map<String, dynamic>.from(user.toMap());
    map.remove('password');
    map.remove('disabledAt');
    map.remove('updatedAt');
    map['isActive'] = isActive ?? user.isActive;
    return map;
  }

  Future<void> _assertUniqueUserCodeNumber(
    String codeNumber, {
    Set<String> excludeDocumentIds = const <String>{},
  }) async {
    final normalized = AccountCodeNumber.normalize(codeNumber);
    if (!AccountCodeNumber.isValid(normalized)) {
      throw StateError('INVALID_CODE_NUMBER');
    }
    final snapshots = await Future.wait(
      <Future<QuerySnapshot<Map<String, dynamic>>>>[
        FirebaseActivityMonitor.track(
          FirebaseActivityKind.read,
          () => _getUserCollectionRef()
              .where('codeNumber', isEqualTo: normalized)
              .limit(10)
              .get(),
          source: 'account.code_lookup',
        ),
        FirebaseActivityMonitor.track(
          FirebaseActivityKind.read,
          () => _getUserCollectionRef()
              .where('phone', isEqualTo: normalized)
              .limit(10)
              .get(),
          source: 'account.phone_lookup',
        ),
        FirebaseActivityMonitor.track(
          FirebaseActivityKind.read,
          () => _getUserCollectionRef()
              .where('handle', isEqualTo: normalized)
              .limit(10)
              .get(),
          source: 'account.handle_lookup',
        ),
      ],
    );
    final duplicated = snapshots
        .expand((snapshot) => snapshot.docs)
        .any((doc) => !excludeDocumentIds.contains(doc.id));
    if (duplicated) {
      throw StateError('CODE_NUMBER_ALREADY_EXISTS');
    }
  }

  String _rootAccountCode(Map<String, dynamic> data) {
    for (final field in <String>['codeNumber', 'phone', 'handle']) {
      final value = AccountCodeNumber.normalize((data[field] ?? '').toString());
      if (AccountCodeNumber.isValid(value)) return value;
    }
    return '';
  }

  Map<String, dynamic> _userCodeReservationPayload({
    required String userId,
    required String codeNumber,
    required String area,
    Object? createdAt,
  }) {
    return <String, dynamic>{
      'userId': userId,
      'codeNumber': codeNumber,
      'area': area,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _removeLegacyScheduleFields(Map<String, dynamic> source) {
    final map = Map<String, dynamic>.from(source);
    map['password'] = FieldValue.delete();
    map['startTime'] = FieldValue.delete();
    map['endTime'] = FieldValue.delete();
    return map;
  }

  Map<String, dynamic> _legacyScheduleDeletes() {
    return <String, dynamic>{
      'startTime': FieldValue.delete(),
      'endTime': FieldValue.delete(),
    };
  }

  Map<String, dynamic> _weekdayScheduleMigrationPayload(UserModel user) {
    final map = user.toMap();
    return <String, dynamic>{
      'fixedHolidays': map['fixedHolidays'],
      'breakDays': map['breakDays'],
      'startTimeByWeekday': map['startTimeByWeekday'],
      'endTimeByWeekday': map['endTimeByWeekday'],
      ..._legacyScheduleDeletes(),
    };
  }

  int? _asInt(dynamic v) => (v is int) ? v : null;

  int _nonNegative(dynamic v) {
    final i = _asInt(v);
    if (i == null || i < 0) return 0;
    return i;
  }

  _ShowAccountCounts _countsFromMeta(Map<String, dynamic> data) {
    final active = _nonNegative(data['activeCount']);
    final inactiveRaw = _asInt(data['inactiveCount']);
    final totalRaw = _asInt(data['totalCount']);
    var inactive = inactiveRaw == null || inactiveRaw < 0 ? 0 : inactiveRaw;
    if ((inactiveRaw == null || inactiveRaw < 0) && totalRaw != null && totalRaw >= active) {
      inactive = totalRaw - active;
    }
    return _ShowAccountCounts(activeCount: active, inactiveCount: inactive);
  }

  bool _metaNeedsCountCompute(Map<String, dynamic> data, bool strict) {
    if (strict) return true;
    final active = _asInt(data['activeCount']);
    final inactive = _asInt(data['inactiveCount']);
    final total = _asInt(data['totalCount']);
    if (active == null || active < 0) return true;
    if (inactive == null || inactive < 0) return true;
    if (total == null || total < 0) return true;
    return total != active + inactive;
  }

  Future<_ShowAccountCounts> _ensureOrSyncAccountCounts({
    required DocumentReference<Map<String, dynamic>> showDocRef,
    required String division,
    required String area,
    required bool strict,
    bool failOnError = false,
    void Function(String)? onDiagnostic,
  }) async {
    final initialized = await AccountInitializationGuard.isInitializedFast(
      firestore: _firestore, companyId: division);
    if (!initialized) throw StateError('ACCOUNT_INITIALIZATION_REQUIRED:$division');
    var stage = 'meta_get';
    try {
      final metaSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => showDocRef.get(), source: 'user_write_service.get');
      if (!metaSnap.exists) throw StateError('ACCOUNT_META_MISSING:$division/$area');
      final meta = metaSnap.data() ?? <String, dynamic>{};
      if (!_metaNeedsCountCompute(meta, strict)) {
        return _countsFromMeta(meta);
      }

      stage = 'company_write_guard';
      final divisionRef = _firestore.collection('divisions').doc(division);
      final before = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => divisionRef.get(const GetOptions(source: Source.server)), source: 'user_write_service.get');
      if (!before.exists || before.data()?['accountWriteLocked'] == true ||
          before.data()?['lifecycleStatus'] == 'closed' ||
          before.data()?['lifecycleStatus'] == 'closing') {
        throw StateError('COMPANY_ACCOUNT_WRITE_BLOCKED:$division');
      }
      final expectedVersion = before.data()?['accountWriteVersion'] is int
          ? before.data()!['accountWriteVersion'] as int : 0;
      stage = 'user_projection_list';
      final qSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => showDocRef.collection('users').get(), source: 'user_write_service.get');
      var active = 0;
      var inactive = 0;
      for (final doc in qSnap.docs) {
        final data = doc.data();
        final isActive = (data['isActive'] as bool?) ?? true;
        if (isActive) {
          active += 1;
        } else {
          inactive += 1;
        }
      }

      final counts = _ShowAccountCounts(activeCount: active, inactiveCount: inactive);
      stage = 'meta_set';
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final currentDivision = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(divisionRef), source: 'user_write_service.get');
        final currentMeta = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showDocRef), source: 'user_write_service.get');
        if (!currentMeta.exists) throw StateError('ACCOUNT_META_MISSING:$division/$area');
        final currentVersion = currentDivision.data()?['accountWriteVersion'] is int
            ? currentDivision.data()!['accountWriteVersion'] as int : 0;
        if (currentVersion != expectedVersion ||
            currentDivision.data()?['accountWriteLocked'] == true ||
            currentDivision.data()?['lifecycleStatus'] == 'closed' ||
            currentDivision.data()?['lifecycleStatus'] == 'closing' ||
            currentMeta.data()?['totalCount'] != metaSnap.data()?['totalCount'] ||
            currentMeta.data()?['activeCount'] != metaSnap.data()?['activeCount'] ||
            currentMeta.data()?['inactiveCount'] != metaSnap.data()?['inactiveCount']) {
          throw StateError('COUNT_REBUILD_CONCURRENT_CHANGE:$division/$area');
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(showDocRef, <String, dynamic>{
          ...counts.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(divisionRef, <String, dynamic>{
          'accountWriteVersion': FieldValue.increment(1),
        }));
      }), source: 'user_write_service.runTransaction');
      onDiagnostic?.call('count_sync_success stage=$stage');
      return counts;
    } on FirebaseException catch (error) {
      onDiagnostic?.call('count_sync_denied_or_failed stage=$stage code=${error.code}');
      if (failOnError || strict) rethrow;
      return const _ShowAccountCounts(activeCount: 0, inactiveCount: 0);
    } catch (error) {
      onDiagnostic?.call('count_sync_exception stage=$stage type=${error.runtimeType}');
      if (failOnError || strict) rethrow;
      return const _ShowAccountCounts(activeCount: 0, inactiveCount: 0);
    }
  }

  void _assertActiveLimit({
    required _ShowAccountCounts counts,
    required int activeDelta,
    required int limit,
  }) {
    if (activeDelta <= 0) return;
    if (counts.activeCount >= limit || counts.activeCount + activeDelta > limit) {
      throw StateError('ACTIVE_LIMIT_REACHED:$limit');
    }
  }

  void _assertTotalLimit({
    required _ShowAccountCounts counts,
    required int totalDelta,
    required int limit,
  }) {
    if (totalDelta <= 0) return;
    if (counts.totalCount >= limit || counts.totalCount + totalDelta > limit) {
      throw StateError('TOTAL_LIMIT_REACHED:$limit');
    }
  }

  Map<String, dynamic> _showMetaPayload({
    required String division,
    required String area,
    required _ShowAccountCounts counts,
  }) {
    return <String, dynamic>{
      'division': division,
      'area': area,
      ...counts.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<DocumentReference<Map<String, dynamic>>> _guardCompanyWrite(
    Transaction tx,
    String companyId,
  ) async {
    final normalized = companyId.trim();
    if (normalized.isEmpty) throw StateError('ACCOUNT_COMPANY_ID_REQUIRED');
    final ref = _firestore.collection('divisions').doc(normalized);
    final company = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(ref), source: 'user_write_service.get');
    if (!company.exists ||
        company.data()?['lifecycleStatus'] == 'closing' ||
        company.data()?['lifecycleStatus'] == 'closed' ||
        company.data()?['accountWriteLocked'] == true) {
      throw StateError('COMPANY_ACCOUNT_WRITE_BLOCKED:$normalized');
    }
    return ref;
  }

  Future<void> addUserCard(UserModel user) async {
    await _assertUniqueUserCodeNumber(user.codeNumber);
    final normalizedCode = AccountCodeNumber.normalize(user.codeNumber);
    final userDocRef = _getUserCollectionRef().doc(user.id);
    final codeDocRef = _getUserCodeCollectionRef().doc(normalizedCode);

    final division = _divisionOfUser(user);
    final area = _areaOfUser(user);
    final showId = _showDocId(division, area);

    final showDocRef = _getUserShowCollectionRef().doc(showId);
    final showUserDocRef = showDocRef.collection('users').doc(user.id);

    final bool wantActive = user.isActive;
    final areaPolicyRef = await AreaAccountLimitPolicy.resolve(
      firestore: _firestore, companyId: division, areaName: area);

    await _ensureOrSyncAccountCounts(
      showDocRef: showDocRef,
      division: division,
      area: area,
      strict: true,
    );

    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final companyRef = await _guardCompanyWrite(tx, division);
        final rootSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(userDocRef), source: 'user_write_service.get');
        final codeSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(codeDocRef), source: 'user_write_service.get');
        if (rootSnap.exists) {
          throw StateError('USER_ALREADY_EXISTS:${user.id}');
        }
        if (codeSnap.exists) {
          throw StateError('CODE_NUMBER_ALREADY_EXISTS');
        }
        final policy = user.isInitialAdmin ? null
            : await CompanyGradePolicyService(firestore: _firestore)
                .loadInTransaction(tx, user.companyId, user.accountGradeId);
        final effectiveUser = policy == null ? user : user.copyWith(
          permissionKeys: policy.permissionKeys.toList(growable: false)..sort(),
        );
        final showSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showDocRef), source: 'user_write_service.get');
        final showData = showSnap.data() ?? <String, dynamic>{};

        if (!showSnap.exists) throw StateError('ACCOUNT_META_MISSING:$division/$area');
        final areaLimits = await AreaAccountLimitPolicy.inTransaction(
          transaction: tx, areaRef: areaPolicyRef,
          companyId: division, areaName: area);
        final activeLimit = areaLimits.active;
        final totalLimit = areaLimits.total;
        final counts0 = _countsFromMeta(showData);

        final existingSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showUserDocRef), source: 'user_write_service.get');
        final existingData = existingSnap.data() ?? <String, dynamic>{};
        final bool existed = existingSnap.exists;
        final bool existingActive = (existingData['isActive'] as bool?) ?? false;

        var activeDelta = 0;
        var inactiveDelta = 0;
        var totalDelta = 0;
        if (!existed) {
          totalDelta = 1;
          if (wantActive) {
            activeDelta = 1;
          } else {
            inactiveDelta = 1;
          }
        } else if (!existingActive && wantActive) {
          activeDelta = 1;
          inactiveDelta = -1;
        } else if (existingActive && !wantActive) {
          activeDelta = -1;
          inactiveDelta = 1;
        }

        _assertTotalLimit(counts: counts0, totalDelta: totalDelta, limit: totalLimit);
        _assertActiveLimit(counts: counts0, activeDelta: activeDelta, limit: activeLimit);

        final counts1 = counts0.applyDeltas(
          activeDelta: activeDelta,
          inactiveDelta: inactiveDelta,
        );

        final loginEmail = user.email.trim().toLowerCase();
        final identityRef = loginEmail.isEmpty ? null
            : _firestore.collection('login_identity_accounts').doc(loginEmail);
        final identityBefore = identityRef == null ? null : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(identityRef), source: 'user_write_service.get');
        if (identityBefore != null && identityBefore.exists) {
          throw StateError('ACCOUNT_EMAIL_IDENTITY_ALREADY_EXISTS');
        }
        if (identityRef != null && identityBefore?.exists != true) {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(identityRef, <String, dynamic>{
            'email': loginEmail,
            'accountId': user.id,
            'companyId': user.companyId,
            'enabled': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }));
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(companyRef, <String, dynamic>{
          'accountWriteVersion': FieldValue.increment(1),
        }));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(userDocRef, _toUserAccountsMap(effectiveUser, isActive: wantActive)));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
          codeDocRef,
          _userCodeReservationPayload(
            userId: user.id,
            codeNumber: normalizedCode,
            area: area,
          ),
        ));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
          showDocRef,
          _showMetaPayload(division: division, area: area, counts: counts1),
          SetOptions(merge: true),
        ));

        final userMap = _removeLegacyScheduleFields(effectiveUser.toMap());
        userMap.remove('passwordHash');
        userMap.remove('passwordSalt');
        userMap.remove('password');
        userMap['updatedAt'] = FieldValue.serverTimestamp();
        userMap['isActive'] = wantActive;
        if (!wantActive) {
          userMap['disabledAt'] = FieldValue.serverTimestamp();
        } else {
          userMap['disabledAt'] = FieldValue.delete();
        }

        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(showUserDocRef, userMap, SetOptions(merge: true)));
      }), source: 'user_write_service.runTransaction');
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> addTabletCard(TabletModel tablet) async {
    _assertCanonicalTabletDocumentId(tablet);
    final documentId = _canonicalTabletDocumentId(tablet);
    await _assertUniqueTabletCodeNumber(tablet.codeNumber);
    final docRef = _getTabletCollectionRef().doc(documentId);
    TabletAccountDiagnostics.record(
      'document_create_start',
      meta: <String, Object?>{
        'documentId': AccountCodeNumber.maskDocumentId(documentId),
        'policy': 'codeNumber-area',
      },
    );
    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        final companyRef = await _guardCompanyWrite(tx, tablet.companyId);
        final existing = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(docRef), source: 'user_write_service.get');
        if (existing.exists) {
          throw StateError('해당 코드번호와 업무 지역으로 등록된 태블릿이 이미 있습니다.');
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(companyRef, <String, dynamic>{
          'accountWriteVersion': FieldValue.increment(1),
        }));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(docRef, tablet.toMap()));
      }), source: 'user_write_service.runTransaction');
      TabletAccountDiagnostics.record(
        'document_create_complete',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
        },
      );
    } on FirebaseException catch (e) {
      TabletAccountDiagnostics.record(
        'document_create_failed',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'error': e.code,
        },
      );
      rethrow;
    } catch (e) {
      TabletAccountDiagnostics.record(
        'document_create_failed',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'error': e.runtimeType,
        },
      );
      rethrow;
    }
  }

  Future<void> _requireEmailIdentityMigrationAccess() async {
    final email = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) throw StateError('ACCOUNT_GOOGLE_IDENTITY_REQUIRED');
    if (DeveloperAccountAuthorization.allowedEmails.contains(email)) return;
    final mapping = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('login_identity_accounts')
        .doc(email).get(const GetOptions(source: Source.server)), source: 'user_write_service.get');
    final accountId = (mapping.data()?['accountId'] ?? '').toString().trim();
    if (accountId.isEmpty || mapping.data()?['enabled'] != true) {
      throw StateError('ACCOUNT_IDENTITY_MIGRATION_REQUIRES_INITIAL_ADMIN');
    }
    final account = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _getUserCollectionRef().doc(accountId)
        .get(const GetOptions(source: Source.server)), source: 'user_write_service.get');
    if (account.data()?['isInitialAdmin'] != true ||
        account.data()?['accountGradeId'] != 'headquartersAdmin' ||
        account.data()?['companyId'] != mapping.data()?['companyId']) {
      throw StateError('ACCOUNT_IDENTITY_MIGRATION_REQUIRES_INITIAL_ADMIN');
    }
  }

  Future<void> _requireNewEmailGateApproval(String email) async {
    if (email.isEmpty) return;
    final actor = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
    if (DeveloperAccountAuthorization.allowedEmails.contains(actor)) return;
    final gate = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('login_gate_admin')
        .doc('authorization').get(const GetOptions(source: Source.server)), source: 'user_write_service.get');
    final allowed = gate.data()?['allow'];
    if (gate.data()?['enabled'] != true || allowed is! List ||
        !allowed.contains(email)) {
      throw StateError('ACCOUNT_NEW_EMAIL_REQUIRES_LOGIN_GATE_APPROVAL');
    }
  }

  Future<void> updateUser(
    UserModel user, {
    String? previousId,
  }) async {
    final previousUserId = (previousId ?? user.id).trim();
    final nextUserId = user.id.trim();
    if (previousUserId != nextUserId) {
      throw StateError('ACCOUNT_ID_CHANGE_REQUIRES_DEVELOPER_MIGRATION');
    }
    final previousUserDocRef = _getUserCollectionRef().doc(previousUserId);
    final nextUserDocRef = _getUserCollectionRef().doc(nextUserId);
    final nextCode = AccountCodeNumber.normalize(user.codeNumber);
    if (!AccountCodeNumber.isValid(nextCode)) {
      throw StateError('INVALID_CODE_NUMBER');
    }
    final nextCodeDocRef = _getUserCodeCollectionRef().doc(nextCode);
    await _assertUniqueUserCodeNumber(
      nextCode,
      excludeDocumentIds: <String>{previousUserId, nextUserId},
    );

    UserModel? prevUser;
    try {
      final prevSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => previousUserDocRef.get(), source: 'user_write_service.get');
      if (prevSnap.exists && prevSnap.data() != null) {
        prevUser = UserModel.fromMap(prevSnap.id, prevSnap.data()!);
      }
    } catch (_) {}

    final registeredEmail = prevUser?.email.trim().toLowerCase() ?? '';
    final requestedEmail = user.email.trim().toLowerCase();
    if (prevUser == null) throw StateError('USER_NOT_FOUND:$previousUserId');
    if (registeredEmail != requestedEmail) {
      if (requestedEmail.isEmpty) throw StateError('ACCOUNT_EMAIL_REQUIRED');
      await _requireEmailIdentityMigrationAccess();
      await _requireNewEmailGateApproval(requestedEmail);
    }
    final newDivision = _divisionOfUser(user);
    final newArea = _areaOfUser(user);
    final newShowId = _showDocId(newDivision, newArea);
    final oldDivision = _divisionOfUser(prevUser);
    final oldArea = _areaOfUser(prevUser);
    final oldShowId = _showDocId(oldDivision, oldArea);
    final identityMoved = previousUserId != nextUserId;
    final showMoved = oldShowId != newShowId;

    final newShowDocRef = _getUserShowCollectionRef().doc(newShowId);
    final newShowUserDocRef = newShowDocRef.collection('users').doc(nextUserId);
    final oldShowDocRef = _getUserShowCollectionRef().doc(oldShowId);
    final oldShowUserDocRef = oldShowDocRef.collection('users').doc(previousUserId);
    final newAreaPolicyRef = await AreaAccountLimitPolicy.resolve(
      firestore: _firestore, companyId: newDivision, areaName: newArea);

    await _ensureOrSyncAccountCounts(
      showDocRef: newShowDocRef,
      division: newDivision,
      area: newArea,
      strict: true,
    );
    if (showMoved) {
      await _ensureOrSyncAccountCounts(
        showDocRef: oldShowDocRef,
        division: oldDivision,
        area: oldArea,
        strict: true,
      );
    }

    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        await _guardCompanyWrite(tx, oldDivision);
        if (newDivision != oldDivision) {
          await _guardCompanyWrite(tx, newDivision);
        }
        final previousRootSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(previousUserDocRef), source: 'user_write_service.get');
        if (!previousRootSnap.exists || previousRootSnap.data() == null) {
          throw StateError('USER_NOT_FOUND:$previousUserId');
        }
        final previousRootData = previousRootSnap.data()!;
        final policy = user.isInitialAdmin ? null
            : await CompanyGradePolicyService(firestore: _firestore)
                .loadInTransaction(tx, user.companyId, user.accountGradeId);
        final effectiveUser = policy == null ? user : user.copyWith(
          permissionKeys: policy.permissionKeys.toList(growable: false)..sort(),
        );
        final oldIdentityEmail = (previousRootData['email'] ?? '')
            .toString().trim().toLowerCase();
        final newIdentityEmail = user.email.trim().toLowerCase();
        final newIdentityRef = newIdentityEmail.isEmpty ? null
            : _firestore.collection('login_identity_accounts').doc(newIdentityEmail);
        final oldIdentityRef = oldIdentityEmail.isEmpty || oldIdentityEmail == newIdentityEmail
            ? null : _firestore.collection('login_identity_accounts').doc(oldIdentityEmail);
        final newIdentitySnap = newIdentityRef == null ? null : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(newIdentityRef), source: 'user_write_service.get');
        final oldIdentitySnap = oldIdentityRef == null ? null : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(oldIdentityRef), source: 'user_write_service.get');
        if (newIdentitySnap != null && newIdentitySnap.exists &&
            newIdentitySnap.data()?['accountId'] != previousUserId &&
            newIdentitySnap.data()?['accountId'] != nextUserId) {
          throw StateError('ACCOUNT_EMAIL_ALREADY_ASSIGNED');
        }
        if (oldIdentitySnap != null && oldIdentitySnap.exists &&
            oldIdentitySnap.data()?['accountId'] != previousUserId) {
          throw StateError('PREVIOUS_EMAIL_IDENTITY_CONFLICT');
        }
        final identityEmailChanged = oldIdentityEmail != newIdentityEmail;
        if (identityEmailChanged && previousRootData['isInitialAdmin'] == true) {
          throw StateError('INITIAL_ADMIN_EMAIL_CHANGE_REQUIRES_DEVELOPER');
        }
        if (identityEmailChanged && oldIdentityEmail.isNotEmpty &&
            oldIdentitySnap?.exists != true) {
          throw StateError('PREVIOUS_EMAIL_IDENTITY_MISSING');
        }
        if (identityEmailChanged && newIdentitySnap?.exists == true &&
            (newIdentitySnap?.data()?['accountId'] != nextUserId ||
             newIdentitySnap?.data()?['companyId'] != user.companyId ||
             newIdentitySnap?.data()?['email'] != newIdentityEmail ||
             newIdentitySnap?.data()?['enabled'] != true)) {
          throw StateError('ACCOUNT_EMAIL_IDENTITY_REQUIRES_REVIEW');
        }
        void synchronizeEmailIdentity() {
          if (!identityEmailChanged) return;
          if (newIdentityRef != null && newIdentitySnap?.exists != true) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(newIdentityRef, <String, dynamic>{
              'email': newIdentityEmail,
              'accountId': nextUserId,
              'companyId': user.companyId,
              'enabled': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }));
          }
          if (oldIdentityRef != null && oldIdentitySnap?.exists == true) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(oldIdentityRef));
          }
        }
        final previousCode = _rootAccountCode(previousRootData);
        final previousCodeDocRef = previousCode.isEmpty
            ? null
            : _getUserCodeCollectionRef().doc(previousCode);
        final sameCode = previousCode == nextCode;
        final nextCodeSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(nextCodeDocRef), source: 'user_write_service.get');
        final previousCodeSnap = sameCode || previousCodeDocRef == null
            ? nextCodeSnap
            : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(previousCodeDocRef), source: 'user_write_service.get');
        final nextCodeOwner = (nextCodeSnap.data()?['userId'] ?? '').toString();
        if (nextCodeSnap.exists &&
            nextCodeOwner != previousUserId &&
            nextCodeOwner != nextUserId) {
          throw StateError('CODE_NUMBER_ALREADY_EXISTS');
        }
        final newShowSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(newShowDocRef), source: 'user_write_service.get');
        final newShowData = newShowSnap.data() ?? <String, dynamic>{};
        if (!newShowSnap.exists) throw StateError('ACCOUNT_META_MISSING:$newDivision/$newArea');
        final newAreaLimits = await AreaAccountLimitPolicy.inTransaction(
          transaction: tx, areaRef: newAreaPolicyRef,
          companyId: newDivision, areaName: newArea);
        final newActiveLimit = newAreaLimits.active;
        final newTotalLimit = newAreaLimits.total;
        final newCounts0 = _countsFromMeta(newShowData);
        final userMap = _removeLegacyScheduleFields(effectiveUser.toMap());
        userMap.remove('passwordHash');
        userMap.remove('passwordSalt');
        userMap.remove('password');
        userMap.remove('isActive');
        userMap.remove('disabledAt');
        userMap['updatedAt'] = FieldValue.serverTimestamp();

        if (!identityMoved && !showMoved) {
          final currentShowUserSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(newShowUserDocRef), source: 'user_write_service.get');
          final currentShowUserData =
              currentShowUserSnap.data() ?? <String, dynamic>{};
          final targetActive = currentShowUserSnap.exists
              ? ((currentShowUserData['isActive'] as bool?) ?? user.isActive)
              : user.isActive;
          var counts1 = newCounts0;
          if (!currentShowUserSnap.exists) {
            final wantActive = targetActive;
            final activeDelta = wantActive ? 1 : 0;
            final inactiveDelta = wantActive ? 0 : 1;
            _assertTotalLimit(
              counts: newCounts0,
              totalDelta: 1,
              limit: newTotalLimit,
            );
            _assertActiveLimit(
              counts: newCounts0,
              activeDelta: activeDelta,
              limit: newActiveLimit,
            );
            counts1 = newCounts0.applyDeltas(
              activeDelta: activeDelta,
              inactiveDelta: inactiveDelta,
            );
            userMap['isActive'] = wantActive;
            userMap['disabledAt'] = wantActive
                ? FieldValue.delete()
                : FieldValue.serverTimestamp();
          } else {
            userMap['isActive'] = targetActive;
            userMap['disabledAt'] = targetActive
                ? FieldValue.delete()
                : (currentShowUserData['disabledAt'] ??
                    FieldValue.serverTimestamp());
          }

          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            nextUserDocRef,
            _toUserAccountsMap(effectiveUser, isActive: targetActive),
            SetOptions(merge: true),
          ));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            newShowDocRef,
            _showMetaPayload(
              division: newDivision,
              area: newArea,
              counts: counts1,
            ),
            SetOptions(merge: true),
          ));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(newShowUserDocRef, userMap, SetOptions(merge: true)));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            nextCodeDocRef,
            _userCodeReservationPayload(
              userId: nextUserId,
              codeNumber: nextCode,
              area: newArea,
              createdAt: nextCodeSnap.data()?['createdAt'],
            ),
            SetOptions(merge: true),
          ));
          if (!sameCode &&
              previousCodeDocRef != null &&
              previousCodeSnap.exists &&
              (previousCodeSnap.data()?['userId'] ?? '').toString() == previousUserId) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(previousCodeDocRef));
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(_firestore.collection('divisions').doc(oldDivision),
              <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)}));
          if (oldDivision != newDivision) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(_firestore.collection('divisions').doc(newDivision),
                <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)}));
          }
          synchronizeEmailIdentity();
          return;
        }

        if (identityMoved && !showMoved) {
          final nextRootSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(nextUserDocRef), source: 'user_write_service.get');
          if (nextRootSnap.exists) {
            throw StateError('USER_ALREADY_EXISTS:$nextUserId');
          }
          final oldShowUserSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(oldShowUserDocRef), source: 'user_write_service.get');
          final nextShowUserSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(newShowUserDocRef), source: 'user_write_service.get');
          if (nextShowUserSnap.exists) {
            throw StateError('USER_ALREADY_EXISTS:$nextUserId');
          }

          final oldShowData = oldShowUserSnap.data() ?? <String, dynamic>{};
          final oldExists = oldShowUserSnap.exists;
          final targetActive = oldExists
              ? ((oldShowData['isActive'] as bool?) ?? user.isActive)
              : user.isActive;
          final disabledAtValue = oldShowData['disabledAt'];
          var counts1 = newCounts0;
          if (!oldExists) {
            final activeDelta = targetActive ? 1 : 0;
            final inactiveDelta = targetActive ? 0 : 1;
            _assertTotalLimit(
              counts: newCounts0,
              totalDelta: 1,
              limit: newTotalLimit,
            );
            _assertActiveLimit(
              counts: newCounts0,
              activeDelta: activeDelta,
              limit: newActiveLimit,
            );
            counts1 = newCounts0.applyDeltas(
              activeDelta: activeDelta,
              inactiveDelta: inactiveDelta,
            );
          }

          final movedUserMap = <String, dynamic>{
            ...userMap,
            'isActive': targetActive,
            if (targetActive) 'disabledAt': FieldValue.delete(),
            if (!targetActive)
              'disabledAt': disabledAtValue ?? FieldValue.serverTimestamp(),
          };
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            nextUserDocRef,
            _toUserAccountsMap(effectiveUser, isActive: targetActive),
          ));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(previousUserDocRef));
          if (oldExists) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(oldShowUserDocRef));
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true)));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            newShowDocRef,
            _showMetaPayload(
              division: newDivision,
              area: newArea,
              counts: counts1,
            ),
            SetOptions(merge: true),
          ));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            nextCodeDocRef,
            _userCodeReservationPayload(
              userId: nextUserId,
              codeNumber: nextCode,
              area: newArea,
              createdAt: nextCodeSnap.data()?['createdAt'],
            ),
            SetOptions(merge: true),
          ));
          if (!sameCode &&
              previousCodeDocRef != null &&
              previousCodeSnap.exists &&
              (previousCodeSnap.data()?['userId'] ?? '').toString() == previousUserId) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(previousCodeDocRef));
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(_firestore.collection('divisions').doc(oldDivision),
              <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)}));
          if (oldDivision != newDivision) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(_firestore.collection('divisions').doc(newDivision),
                <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)}));
          }
          synchronizeEmailIdentity();
          return;
        }

        final oldShowSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(oldShowDocRef), source: 'user_write_service.get');
        final oldShowData = oldShowSnap.data() ?? <String, dynamic>{};
        final oldCounts0 = _countsFromMeta(oldShowData);
        final oldUserSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(oldShowUserDocRef), source: 'user_write_service.get');
        final newUserSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(newShowUserDocRef), source: 'user_write_service.get');
        if (identityMoved) {
          final nextRootSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(nextUserDocRef), source: 'user_write_service.get');
          if (nextRootSnap.exists || newUserSnap.exists) {
            throw StateError('USER_ALREADY_EXISTS:$nextUserId');
          }
        }

        final oldExists = oldUserSnap.exists;
        final newExists = newUserSnap.exists;
        final oldData = oldUserSnap.data() ?? <String, dynamic>{};
        final newData = newUserSnap.data() ?? <String, dynamic>{};
        final oldActive = (oldData['isActive'] as bool?) ?? false;
        final newActive = (newData['isActive'] as bool?) ?? false;
        final targetActive = oldExists
            ? oldActive
            : (newExists ? newActive : user.isActive);
        final disabledAtValue = oldExists
            ? oldData['disabledAt']
            : newData['disabledAt'];
        final oldActiveDelta = oldExists && oldActive ? -1 : 0;
        final oldInactiveDelta = oldExists && !oldActive ? -1 : 0;
        final newActiveDelta = targetActive
            ? (newExists && newActive ? 0 : 1)
            : (newExists && newActive ? -1 : 0);
        final newInactiveDelta = targetActive
            ? (newExists && !newActive ? -1 : 0)
            : (newExists && !newActive ? 0 : 1);
        final newTotalDelta = newExists ? 0 : 1;

        _assertTotalLimit(
          counts: newCounts0,
          totalDelta: newTotalDelta,
          limit: newTotalLimit,
        );
        _assertActiveLimit(
          counts: newCounts0,
          activeDelta: newActiveDelta,
          limit: newActiveLimit,
        );

        final oldCounts1 = oldCounts0.applyDeltas(
          activeDelta: oldActiveDelta,
          inactiveDelta: oldInactiveDelta,
        );
        final newCounts1 = newCounts0.applyDeltas(
          activeDelta: newActiveDelta,
          inactiveDelta: newInactiveDelta,
        );

        if (identityMoved) {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            nextUserDocRef,
            _toUserAccountsMap(effectiveUser, isActive: targetActive),
          ));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(previousUserDocRef));
        } else {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            nextUserDocRef,
            _toUserAccountsMap(effectiveUser, isActive: targetActive),
            SetOptions(merge: true),
          ));
        }
        if (oldExists) {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(oldShowUserDocRef));
        }

        final movedUserMap = <String, dynamic>{
          ...userMap,
          'isActive': targetActive,
          if (targetActive) 'disabledAt': FieldValue.delete(),
          if (!targetActive)
            'disabledAt': disabledAtValue ?? FieldValue.serverTimestamp(),
        };
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true)));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
          newShowDocRef,
          _showMetaPayload(
            division: newDivision,
            area: newArea,
            counts: newCounts1,
          ),
          SetOptions(merge: true),
        ));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
          oldShowDocRef,
          _showMetaPayload(
            division: oldDivision,
            area: oldArea,
            counts: oldCounts1,
          ),
          SetOptions(merge: true),
        ));
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
          nextCodeDocRef,
          _userCodeReservationPayload(
            userId: nextUserId,
            codeNumber: nextCode,
            area: newArea,
            createdAt: nextCodeSnap.data()?['createdAt'],
          ),
          SetOptions(merge: true),
        ));
        if (!sameCode &&
            previousCodeDocRef != null &&
            previousCodeSnap.exists &&
            (previousCodeSnap.data()?['userId'] ?? '').toString() == previousUserId) {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(previousCodeDocRef));
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(_firestore.collection('divisions').doc(oldDivision),
            <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)}));
        if (oldDivision != newDivision) {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(_firestore.collection('divisions').doc(newDivision),
              <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)}));
        }
        synchronizeEmailIdentity();
      }), source: 'user_write_service.runTransaction');
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> updateTablet(
    TabletModel tablet, {
    String? previousId,
  }) async {
    _assertCanonicalTabletDocumentId(tablet);
    final documentId = _canonicalTabletDocumentId(tablet);
    final previous = (previousId ?? '').trim();
    await _assertUniqueTabletCodeNumber(
      tablet.codeNumber,
      excludeDocumentId: previous.isEmpty ? documentId : previous,
      allowLegacyNumeric: true,
    );
    final nextRef = _getTabletCollectionRef().doc(documentId);
    final moving = previous.isNotEmpty && previous != documentId;
    TabletAccountDiagnostics.record(
      moving ? 'document_move_start' : 'document_update_start',
      meta: <String, Object?>{
        'previousId': previous.isEmpty
            ? '-'
            : AccountCodeNumber.maskDocumentId(previous),
        'documentId': AccountCodeNumber.maskDocumentId(documentId),
        'policy': 'codeNumber-area',
      },
    );
    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        await _guardCompanyWrite(tx, tablet.companyId);
        if (moving) {
          final existing = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(nextRef), source: 'user_write_service.get');
          if (existing.exists) {
            throw StateError('해당 코드번호와 업무 지역으로 등록된 태블릿이 이미 있습니다.');
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(nextRef, tablet.toMap()));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(_getTabletCollectionRef().doc(previous)));
          return;
        }
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(nextRef, tablet.toMap(), SetOptions(merge: true)));
      }), source: 'user_write_service.runTransaction');
      TabletAccountDiagnostics.record(
        moving ? 'document_move_complete' : 'document_update_complete',
        meta: <String, Object?>{
          'previousId': previous.isEmpty
              ? '-'
              : AccountCodeNumber.maskDocumentId(previous),
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
        },
      );
    } on FirebaseException catch (e) {
      TabletAccountDiagnostics.record(
        moving ? 'document_move_failed' : 'document_update_failed',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'error': e.code,
        },
      );
      rethrow;
    } catch (e) {
      TabletAccountDiagnostics.record(
        moving ? 'document_move_failed' : 'document_update_failed',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(documentId),
          'error': e.runtimeType,
        },
      );
      rethrow;
    }
  }

  Future<void> setUserActiveStatus(
    String userId, {
    required bool isActive,
  }) async {
    final userDocRef = _getUserCollectionRef().doc(userId);

    try {
      final snap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => userDocRef.get(), source: 'user_write_service.get');
      if (!snap.exists || snap.data() == null) {
        throw Exception('setUserActiveStatus 실패: user_accounts 문서가 없습니다. (userId=$userId)');
      }

      final current = UserModel.fromMap(snap.id, snap.data()!);

      final division = _divisionOfUser(current);
      final area = _areaOfUser(current);
      final showId = _showDocId(division, area);

      final showDocRef = _getUserShowCollectionRef().doc(showId);
      final showUserDocRef = showDocRef.collection('users').doc(userId);
      final areaPolicyRef = await AreaAccountLimitPolicy.resolve(
        firestore: _firestore, companyId: division, areaName: area);

      await _ensureOrSyncAccountCounts(
        showDocRef: showDocRef,
        division: division,
        area: area,
        strict: true,
      );

      await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
        await _guardCompanyWrite(tx, division);
        final showSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showDocRef), source: 'user_write_service.get');
        final showData = showSnap.data() ?? <String, dynamic>{};

        if (!showSnap.exists) throw StateError('ACCOUNT_META_MISSING:$division/$area');
        final areaLimits = await AreaAccountLimitPolicy.inTransaction(
          transaction: tx, areaRef: areaPolicyRef,
          companyId: division, areaName: area);
        final int activeLimit = areaLimits.active;
        final counts0 = _countsFromMeta(showData);

        final userSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showUserDocRef), source: 'user_write_service.get');
        if (!userSnap.exists) {
          throw StateError('SHOW_USER_DOC_MISSING:showId=$showId userId=$userId');
        }

        final userData = userSnap.data() ?? <String, dynamic>{};
        final bool currentActive = (userData['isActive'] as bool?) ?? true;
        final scheduleMigration = _weekdayScheduleMigrationPayload(current);
        final rootStatusPayload = <String, dynamic>{
          ...scheduleMigration,
          'isActive': isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final viewStatusPayload = <String, dynamic>{
          ...scheduleMigration,
          'password': FieldValue.delete(),
          'isActive': isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(userDocRef, rootStatusPayload, SetOptions(merge: true)));

        if (currentActive == isActive) {
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            showUserDocRef,
            <String, dynamic>{
              ...viewStatusPayload,
              'disabledAt': isActive
                  ? FieldValue.delete()
                  : (userData['disabledAt'] ?? FieldValue.serverTimestamp()),
            },
            SetOptions(merge: true),
          ));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            showDocRef,
            _showMetaPayload(division: division, area: area, counts: counts0),
            SetOptions(merge: true),
          ));
          return;
        }

        var activeDelta = 0;
        var inactiveDelta = 0;
        if (isActive) {
          activeDelta = 1;
          inactiveDelta = -1;
          _assertActiveLimit(counts: counts0, activeDelta: activeDelta, limit: activeLimit);

          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            showUserDocRef,
            {
              ...viewStatusPayload,
              'disabledAt': FieldValue.delete(),
            },
            SetOptions(merge: true),
          ));
        } else {
          activeDelta = -1;
          inactiveDelta = 1;
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            showUserDocRef,
            {
              ...viewStatusPayload,
              'disabledAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          ));
        }

        final counts1 = counts0.applyDeltas(
          activeDelta: activeDelta,
          inactiveDelta: inactiveDelta,
        );
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
          showDocRef,
          _showMetaPayload(division: division, area: area, counts: counts1),
          SetOptions(merge: true),
        ));
      }), source: 'user_write_service.runTransaction');
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deleteUsers(
    List<String> ids, {
    void Function(String)? onDiagnostic,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    onDiagnostic?.call(
      'firebase_identity present=${authUser != null} anonymous=${authUser?.isAnonymous ?? false} providers=${authUser?.providerData.map((provider) => provider.providerId).join(',') ?? 'none'}',
    );
    for (final id in ids) {
      final userDocRef = _getUserCollectionRef().doc(id);
      var stage = 'account_get';
      try {
        onDiagnostic?.call('account_get_started collection=user_accounts');
        final snap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => userDocRef.get(), source: 'user_write_service.get');
        if (!snap.exists || snap.data() == null) {
          onDiagnostic?.call('account_missing_delete_attempt collection=user_accounts');
          stage = 'missing_account_delete';
          await FirebaseActivityMonitor.track(FirebaseActivityKind.delete, () => userDocRef.delete(), source: 'user_write_service.delete');
          onDiagnostic?.call('account_missing_delete_completed');
          continue;
        }
        final prevUser = UserModel.fromMap(snap.id, snap.data()!);
        onDiagnostic?.call('account_get_success');
        final division = _divisionOfUser(prevUser);
        final area = _areaOfUser(prevUser);
        final showId = _showDocId(division, area);
        final showDocRef = _getUserShowCollectionRef().doc(showId);
        final showUserDocRef = showDocRef.collection('users').doc(id);
        final normalizedCode = AccountCodeNumber.normalize(prevUser.codeNumber);
        final codeDocRef = normalizedCode.isEmpty
            ? null
            : _getUserCodeCollectionRef().doc(normalizedCode);
        onDiagnostic?.call(
          'delete_plan projection=true code_reservation=${codeDocRef != null} developer_manual_code=${AccountCodeNumber.isDeveloperManualCode(normalizedCode)}',
        );

        stage = 'count_sync';
        onDiagnostic?.call('count_sync_started collection=user_accounts_show');
        await _ensureOrSyncAccountCounts(
          showDocRef: showDocRef,
          division: division,
          area: area,
          strict: true,
          failOnError: true,
          onDiagnostic: onDiagnostic,
        );

        stage = 'transaction_start';
        onDiagnostic?.call('transaction_started');
        await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
          await _guardCompanyWrite(tx, division);
          stage = 'transaction_code_get';
          final codeSnap = codeDocRef == null ? null : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(codeDocRef), source: 'user_write_service.get');
          if (codeSnap != null && codeSnap.exists) {
            final owner = (codeSnap.data()?['userId'] ?? '').toString();
            if (owner.isNotEmpty && owner != id) {
              throw StateError('USER_CODE_RESERVATION_MISMATCH:$normalizedCode');
            }
          }
          stage = 'transaction_meta_get';
          final showSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showDocRef), source: 'user_write_service.get');
          final showData = showSnap.data() ?? <String, dynamic>{};
          final counts0 = _countsFromMeta(showData);
          stage = 'transaction_projection_get';
          final showUserSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(showUserDocRef), source: 'user_write_service.get');
          var counts1 = counts0;
          if (showUserSnap.exists) {
            final d = showUserSnap.data() ?? <String, dynamic>{};
            final wasActive = (d['isActive'] as bool?) ?? false;
            counts1 = counts0.applyDeltas(
              activeDelta: wasActive ? -1 : 0,
              inactiveDelta: wasActive ? 0 : -1,
            );
          }
          final email = prevUser.email.trim().toLowerCase();
          final identityRef = email.isEmpty ? null
              : _firestore.collection('login_identity_accounts').doc(email);
          final identityBefore = identityRef == null ? null : await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(identityRef), source: 'user_write_service.get');
          if (identityBefore != null && identityBefore.exists &&
              identityBefore.data()?['accountId'] != id) {
            throw StateError('ACCOUNT_IDENTITY_RESERVATION_MISMATCH');
          }
          stage = 'transaction_commit';
          if (identityRef != null && identityBefore?.exists == true) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(identityRef));
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(showUserDocRef));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(userDocRef));
          if (codeDocRef != null && codeSnap != null && codeSnap.exists) {
            FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(codeDocRef));
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            showDocRef,
            _showMetaPayload(division: division, area: area, counts: counts1),
            SetOptions(merge: true),
          ));
        }), source: 'user_write_service.runTransaction');
        onDiagnostic?.call('transaction_committed account_delete_success');
      } on FirebaseException catch (error) {
        onDiagnostic?.call(
          'delete_firestore_failure stage=$stage code=${error.code} message=${error.message ?? 'unknown'}',
        );
        rethrow;
      } catch (error) {
        onDiagnostic?.call('delete_exception stage=$stage type=${error.runtimeType}');
        rethrow;
      }
    }
  }

  Future<void> deleteTablets(List<String> ids) async {
    for (final id in ids) {
      final docRef = _getTabletCollectionRef().doc(id);
      try {
        await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((tx) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
          final tablet = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(docRef), source: 'user_write_service.get');
          if (!tablet.exists) return;
          final company = (tablet.data()?['companyId'] ?? '').toString();
          final companyRef = await _guardCompanyWrite(tx, company);
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => tx.update(companyRef, <String, dynamic>{
            'accountWriteVersion': FieldValue.increment(1),
          }));
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => tx.delete(docRef));
        }), source: 'user_write_service.runTransaction');
      } on FirebaseException {
        rethrow;
      } catch (_) {
        rethrow;
      }
    }
  }
}
