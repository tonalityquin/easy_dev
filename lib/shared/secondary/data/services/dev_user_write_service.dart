import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../features/account/domain/models/user/user_model.dart';
import '../../../auth/account_code_number.dart';

class _DevAccountCounts {
  const _DevAccountCounts({
    required this.activeCount,
    required this.inactiveCount,
  });

  final int activeCount;
  final int inactiveCount;

  int get totalCount => activeCount + inactiveCount;

  _DevAccountCounts applyDeltas({
    int activeDelta = 0,
    int inactiveDelta = 0,
  }) {
    var active = activeCount + activeDelta;
    var inactive = inactiveCount + inactiveDelta;
    if (active < 0) active = 0;
    if (inactive < 0) inactive = 0;
    return _DevAccountCounts(
      activeCount: active,
      inactiveCount: inactive,
    );
  }

  Map<String, int> toMap() {
    return <String, int>{
      'activeCount': activeCount,
      'inactiveCount': inactiveCount,
      'totalCount': totalCount,
    };
  }
}

class DevUserWriteService {
  DevUserWriteService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('user_accounts');

  CollectionReference<Map<String, dynamic>> get _shows =>
      _firestore.collection('user_accounts_show');

  CollectionReference<Map<String, dynamic>> get _codes =>
      _firestore.collection('user_account_codes');

  String _showId(String division, String area) {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
      throw StateError('PRIMARY_ASSIGNMENT_REQUIRED');
    }
    return '$normalizedDivision-$normalizedArea';
  }

  Map<String, dynamic> _rootPayload(UserModel user) {
    final map = Map<String, dynamic>.from(user.toMap());
    map.remove('password');
    map.remove('disabledAt');
    map.remove('updatedAt');
    return map;
  }

  Map<String, dynamic> _projectionPayload(UserModel user) {
    final map = Map<String, dynamic>.from(user.toMap());
    map['password'] = FieldValue.delete();
    map['passwordHash'] = FieldValue.delete();
    map['passwordSalt'] = FieldValue.delete();
    map['startTime'] = FieldValue.delete();
    map['endTime'] = FieldValue.delete();
    return map;
  }


  String _rootAccountCode(Map<String, dynamic> data) {
    for (final field in <String>['codeNumber', 'phone', 'handle']) {
      final value = AccountCodeNumber.normalize((data[field] ?? '').toString());
      if (AccountCodeNumber.isValid(value)) return value;
    }
    return '';
  }

  Map<String, dynamic> _reservationPayload({
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
        _users.where('codeNumber', isEqualTo: normalized).limit(10).get(),
        _users.where('phone', isEqualTo: normalized).limit(10).get(),
        _users.where('handle', isEqualTo: normalized).limit(10).get(),
      ],
    );
    final duplicated = snapshots
        .expand((snapshot) => snapshot.docs)
        .any((doc) => !excludeDocumentIds.contains(doc.id));
    if (duplicated) {
      throw StateError('CODE_NUMBER_ALREADY_EXISTS');
    }
  }

  int? _intValue(dynamic value) => value is int ? value : null;

  int _nonNegative(dynamic value) {
    final parsed = _intValue(value);
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  int? _configuredLimit(dynamic value) {
    if (value is int && value >= 0) return value;
    return null;
  }

  _DevAccountCounts _countsFromMeta(Map<String, dynamic> data) {
    final active = _nonNegative(data['activeCount']);
    final inactiveRaw = _intValue(data['inactiveCount']);
    final totalRaw = _intValue(data['totalCount']);
    var inactive = inactiveRaw == null || inactiveRaw < 0 ? 0 : inactiveRaw;
    if ((inactiveRaw == null || inactiveRaw < 0) &&
        totalRaw != null &&
        totalRaw >= active) {
      inactive = totalRaw - active;
    }
    return _DevAccountCounts(
      activeCount: active,
      inactiveCount: inactive,
    );
  }

  bool _metaNeedsCountCompute(Map<String, dynamic> data) {
    final active = _intValue(data['activeCount']);
    final inactive = _intValue(data['inactiveCount']);
    final total = _intValue(data['totalCount']);
    if (active == null || active < 0) return true;
    if (inactive == null || inactive < 0) return true;
    if (total == null || total < 0) return true;
    return total != active + inactive;
  }

  Future<void> _ensureAccountCounts({
    required DocumentReference<Map<String, dynamic>> showRef,
    required String division,
    required String area,
    void Function(String message)? log,
  }) async {
    final metaSnap = await showRef.get();
    final meta = metaSnap.data() ?? <String, dynamic>{};
    if (!_metaNeedsCountCompute(meta)) {
      log?.call(
        'DevUserWriteService count meta 사용: division=$division area=$area active=${meta['activeCount']} inactive=${meta['inactiveCount']} total=${meta['totalCount']}',
      );
      return;
    }

    final divisionRef = _firestore.collection('divisions').doc(division);
    final before = await divisionRef.get(const GetOptions(source: Source.server));
    if (!before.exists || before.data()?['accountWriteLocked'] == true ||
        before.data()?['lifecycleStatus'] == 'closed' ||
        before.data()?['lifecycleStatus'] == 'closing') {
      throw StateError('COMPANY_ACCOUNT_WRITE_BLOCKED:$division');
    }
    final expectedVersion = before.data()?['accountWriteVersion'] is int
        ? before.data()!['accountWriteVersion'] as int : 0;
    final usersSnap = await showRef.collection('users').get();
    var active = 0;
    var inactive = 0;
    for (final doc in usersSnap.docs) {
      final isActive = (doc.data()['isActive'] as bool?) ?? true;
      if (isActive) {
        active += 1;
      } else {
        inactive += 1;
      }
    }
    final counts = _DevAccountCounts(
      activeCount: active,
      inactiveCount: inactive,
    );
    await _firestore.runTransaction((tx) async {
      final currentDivision = await tx.get(divisionRef);
      final currentMeta = await tx.get(showRef);
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
      tx.set(showRef, <String, dynamic>{
        'division': division,
        'area': area,
        ...counts.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.update(divisionRef, <String, dynamic>{
        'accountWriteVersion': FieldValue.increment(1),
      });
    });
    log?.call(
      'DevUserWriteService count meta 복구: division=$division area=$area active=$active inactive=$inactive total=${counts.totalCount}',
    );
  }

  void _assertConfiguredLimits(Map<String, dynamic> data) {
    if (_configuredLimit(data['activeLimit']) == null ||
        _configuredLimit(data['totalLimit']) == null) {
      throw StateError('ACCOUNT_LIMIT_NOT_CONFIGURED');
    }
  }

  void _assertActiveLimit({
    required _DevAccountCounts counts,
    required int activeDelta,
    required int limit,
  }) {
    if (activeDelta <= 0) return;
    if (counts.activeCount >= limit ||
        counts.activeCount + activeDelta > limit) {
      throw StateError('ACTIVE_LIMIT_REACHED:$limit');
    }
  }

  void _assertTotalLimit({
    required _DevAccountCounts counts,
    required int totalDelta,
    required int limit,
  }) {
    if (totalDelta <= 0) return;
    if (counts.totalCount >= limit ||
        counts.totalCount + totalDelta > limit) {
      throw StateError('TOTAL_LIMIT_REACHED:$limit');
    }
  }

  Map<String, dynamic> _metaPayload({
    required String division,
    required String area,
    required _DevAccountCounts counts,
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
    final company = await tx.get(ref);
    if (!company.exists ||
        company.data()?['lifecycleStatus'] == 'closing' ||
        company.data()?['lifecycleStatus'] == 'closed' ||
        company.data()?['accountWriteLocked'] == true) {
      throw StateError('COMPANY_ACCOUNT_WRITE_BLOCKED:$normalized');
    }
    return ref;
  }

  Future<void> createUser({
    required UserModel user,
    required String division,
    required String area,
    void Function(String message)? log,
  }) async {
    await _assertUniqueUserCodeNumber(user.codeNumber);
    final normalizedCode = AccountCodeNumber.normalize(user.codeNumber);
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    final showId = _showId(normalizedDivision, normalizedArea);
    final rootRef = _users.doc(user.id);
    final codeRef = _codes.doc(normalizedCode);
    final showRef = _shows.doc(showId);
    final showUserRef = showRef.collection('users').doc(user.id);

    log?.call(
      'DevUserWriteService create 시작: id=${AccountCodeNumber.maskDocumentId(user.id)} division=$normalizedDivision area=$normalizedArea',
    );

    await _ensureAccountCounts(
      showRef: showRef,
      division: normalizedDivision,
      area: normalizedArea,
      log: log,
    );

    await _firestore.runTransaction((tx) async {
      final companyRef = await _guardCompanyWrite(tx, user.companyId);
      final rootSnap = await tx.get(rootRef);
      final codeSnap = await tx.get(codeRef);
      if (rootSnap.exists) {
        throw StateError('USER_ALREADY_EXISTS:${user.id}');
      }
      if (codeSnap.exists) {
        throw StateError('CODE_NUMBER_ALREADY_EXISTS');
      }

      final showSnap = await tx.get(showRef);
      final showData = showSnap.data() ?? <String, dynamic>{};
      _assertConfiguredLimits(showData);
      final activeLimit = _configuredLimit(showData['activeLimit'])!;
      final totalLimit = _configuredLimit(showData['totalLimit'])!;
      final counts0 = _countsFromMeta(showData);

      final showUserSnap = await tx.get(showUserRef);
      if (showUserSnap.exists) {
        throw StateError('SHOW_USER_ALREADY_EXISTS:$showId/${user.id}');
      }

      final activeDelta = user.isActive ? 1 : 0;
      final inactiveDelta = user.isActive ? 0 : 1;
      _assertTotalLimit(
        counts: counts0,
        totalDelta: 1,
        limit: totalLimit,
      );
      _assertActiveLimit(
        counts: counts0,
        activeDelta: activeDelta,
        limit: activeLimit,
      );
      final counts1 = counts0.applyDeltas(
        activeDelta: activeDelta,
        inactiveDelta: inactiveDelta,
      );

      final rootMap = <String, dynamic>{
        ..._rootPayload(user),
        'isActive': user.isActive,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final showMap = _projectionPayload(user)
        ..['createdAt'] = FieldValue.serverTimestamp()
        ..['updatedAt'] = FieldValue.serverTimestamp()
        ..['isActive'] = user.isActive
        ..['disabledAt'] = user.isActive
            ? FieldValue.delete()
            : FieldValue.serverTimestamp();

      tx.update(companyRef, <String, dynamic>{
        'accountWriteVersion': FieldValue.increment(1),
      });
      tx.set(rootRef, rootMap);
      tx.set(
        codeRef,
        _reservationPayload(
          userId: user.id,
          codeNumber: normalizedCode,
          area: normalizedArea,
        ),
      );
      tx.set(
        showRef,
        _metaPayload(
          division: normalizedDivision,
          area: normalizedArea,
          counts: counts1,
        ),
        SetOptions(merge: true),
      );
      tx.set(showUserRef, showMap, SetOptions(merge: true));
    });

    log?.call(
      'DevUserWriteService create 완료: id=${AccountCodeNumber.maskDocumentId(user.id)} show=$showId',
    );
  }

  Future<void> updateUser({
    required UserModel user,
    required String previousUserId,
    required String previousDivision,
    required String previousArea,
    required String targetDivision,
    required String targetArea,
    void Function(String message)? log,
  }) async {
    final oldUserId = previousUserId.trim();
    final newUserId = user.id.trim();
    final newCode = AccountCodeNumber.normalize(user.codeNumber);
    if (!AccountCodeNumber.isValid(newCode)) {
      throw StateError('INVALID_CODE_NUMBER');
    }
    await _assertUniqueUserCodeNumber(
      newCode,
      excludeDocumentIds: <String>{oldUserId, newUserId},
    );
    final oldDivision = previousDivision.trim();
    final oldArea = previousArea.trim();
    final newDivision = targetDivision.trim();
    final newArea = targetArea.trim();
    final oldShowId = _showId(oldDivision, oldArea);
    final newShowId = _showId(newDivision, newArea);
    final idChanged = oldUserId != newUserId;
    final showChanged = oldShowId != newShowId;

    final oldRootRef = _users.doc(oldUserId);
    final newRootRef = _users.doc(newUserId);
    final oldShowRef = _shows.doc(oldShowId);
    final newShowRef = _shows.doc(newShowId);
    final oldShowUserRef = oldShowRef.collection('users').doc(oldUserId);
    final newShowUserRef = newShowRef.collection('users').doc(newUserId);

    log?.call(
      'DevUserWriteService update 시작: oldId=${AccountCodeNumber.maskDocumentId(oldUserId)} newId=${AccountCodeNumber.maskDocumentId(newUserId)} old=$oldShowId new=$newShowId',
    );

    await _ensureAccountCounts(
      showRef: newShowRef,
      division: newDivision,
      area: newArea,
      log: log,
    );
    if (showChanged) {
      await _ensureAccountCounts(
        showRef: oldShowRef,
        division: oldDivision,
        area: oldArea,
        log: log,
      );
    }

    await _firestore.runTransaction((tx) async {
      await _guardCompanyWrite(tx, oldDivision);
      if (newDivision != oldDivision) {
        await _guardCompanyWrite(tx, newDivision);
      }
      final oldRootSnap = await tx.get(oldRootRef);
      if (!oldRootSnap.exists || oldRootSnap.data() == null) {
        throw StateError('USER_NOT_FOUND:$oldUserId');
      }
      final oldRootData = oldRootSnap.data()!;
      final oldCode = _rootAccountCode(oldRootData);
      final oldCodeRef = oldCode.isEmpty ? null : _codes.doc(oldCode);
      final newCodeRef = _codes.doc(newCode);
      final sameCode = oldCode == newCode;
      final newCodeSnap = await tx.get(newCodeRef);
      final oldCodeSnap = sameCode || oldCodeRef == null
          ? newCodeSnap
          : await tx.get(oldCodeRef);
      final newCodeOwner = (newCodeSnap.data()?['userId'] ?? '').toString();
      if (newCodeSnap.exists &&
          newCodeOwner != oldUserId &&
          newCodeOwner != newUserId) {
        throw StateError('CODE_NUMBER_ALREADY_EXISTS');
      }
      if (idChanged) {
        final newRootSnap = await tx.get(newRootRef);
        if (newRootSnap.exists) {
          throw StateError('USER_ALREADY_EXISTS:$newUserId');
        }
      }

      final newShowSnap = await tx.get(newShowRef);
      final newShowData = newShowSnap.data() ?? <String, dynamic>{};
      final newCounts0 = _countsFromMeta(newShowData);
      final oldShowSnap = showChanged ? await tx.get(oldShowRef) : newShowSnap;
      final oldShowData = oldShowSnap.data() ?? <String, dynamic>{};
      final oldCounts0 = _countsFromMeta(oldShowData);

      final oldShowUserSnap = await tx.get(oldShowUserRef);
      final oldShowUserData = oldShowUserSnap.data() ?? <String, dynamic>{};
      final oldShowUserExists = oldShowUserSnap.exists;
      final sameProjectionRef = !showChanged && !idChanged;
      final newShowUserSnap = sameProjectionRef
          ? oldShowUserSnap
          : await tx.get(newShowUserRef);
      if (!sameProjectionRef && newShowUserSnap.exists) {
        throw StateError('SHOW_USER_ALREADY_EXISTS:$newShowId/$newUserId');
      }

      final oldActive =
          (oldShowUserData['isActive'] as bool?) ?? user.isActive;
      final targetActive = oldShowUserExists ? oldActive : user.isActive;
      var oldCounts1 = oldCounts0;
      var newCounts1 = newCounts0;

      if (showChanged) {
        if (oldShowUserExists) {
          oldCounts1 = oldCounts0.applyDeltas(
            activeDelta: oldActive ? -1 : 0,
            inactiveDelta: oldActive ? 0 : -1,
          );
        }
        _assertConfiguredLimits(newShowData);
        final activeLimit = _configuredLimit(newShowData['activeLimit'])!;
        final totalLimit = _configuredLimit(newShowData['totalLimit'])!;
        _assertTotalLimit(
          counts: newCounts0,
          totalDelta: 1,
          limit: totalLimit,
        );
        _assertActiveLimit(
          counts: newCounts0,
          activeDelta: targetActive ? 1 : 0,
          limit: activeLimit,
        );
        newCounts1 = newCounts0.applyDeltas(
          activeDelta: targetActive ? 1 : 0,
          inactiveDelta: targetActive ? 0 : 1,
        );
      } else if (!oldShowUserExists) {
        _assertConfiguredLimits(newShowData);
        final activeLimit = _configuredLimit(newShowData['activeLimit'])!;
        final totalLimit = _configuredLimit(newShowData['totalLimit'])!;
        _assertTotalLimit(
          counts: newCounts0,
          totalDelta: 1,
          limit: totalLimit,
        );
        _assertActiveLimit(
          counts: newCounts0,
          activeDelta: targetActive ? 1 : 0,
          limit: activeLimit,
        );
        newCounts1 = newCounts0.applyDeltas(
          activeDelta: targetActive ? 1 : 0,
          inactiveDelta: targetActive ? 0 : 1,
        );
      }

      final rootCreatedAt = oldRootSnap.data()?['createdAt'];
      final rootMap = <String, dynamic>{
        ..._rootPayload(user),
        'isActive': targetActive,
        'createdAt': rootCreatedAt ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final showCreatedAt = oldShowUserData['createdAt'] ?? rootCreatedAt;
      final showMap = _projectionPayload(user)
        ..['createdAt'] = showCreatedAt ?? FieldValue.serverTimestamp()
        ..['updatedAt'] = FieldValue.serverTimestamp()
        ..['isActive'] = targetActive
        ..['disabledAt'] = targetActive
            ? FieldValue.delete()
            : (oldShowUserData['disabledAt'] ?? FieldValue.serverTimestamp());

      if (idChanged) {
        tx.set(newRootRef, rootMap);
        tx.delete(oldRootRef);
      } else {
        tx.set(newRootRef, rootMap, SetOptions(merge: true));
      }
      if ((showChanged || idChanged) && oldShowUserExists) {
        tx.delete(oldShowUserRef);
      }
      tx.set(newShowUserRef, showMap, SetOptions(merge: true));
      tx.set(
        newShowRef,
        _metaPayload(
          division: newDivision,
          area: newArea,
          counts: newCounts1,
        ),
        SetOptions(merge: true),
      );
      if (showChanged) {
        tx.set(
          oldShowRef,
          _metaPayload(
            division: oldDivision,
            area: oldArea,
            counts: oldCounts1,
          ),
          SetOptions(merge: true),
        );
      }
      tx.set(
        newCodeRef,
        _reservationPayload(
          userId: newUserId,
          codeNumber: newCode,
          area: newArea,
          createdAt: newCodeSnap.data()?['createdAt'],
        ),
        SetOptions(merge: true),
      );
      if (!sameCode &&
          oldCodeRef != null &&
          oldCodeSnap.exists &&
          (oldCodeSnap.data()?['userId'] ?? '').toString() == oldUserId) {
        tx.delete(oldCodeRef);
      }
      tx.update(_firestore.collection('divisions').doc(oldDivision),
          <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)});
      if (oldDivision != newDivision) {
        tx.update(_firestore.collection('divisions').doc(newDivision),
            <String, dynamic>{'accountWriteVersion': FieldValue.increment(1)});
      }
    });

    log?.call(
      'DevUserWriteService update 완료: oldId=$oldUserId newId=$newUserId old=$oldShowId new=$newShowId',
    );
  }
}
