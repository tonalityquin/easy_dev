import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../shared/auth/account_code_number.dart';
import '../../applications/tablet_account_diagnostics.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';

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
        (field) => _getTabletCollectionRef()
            .where(field, isEqualTo: normalized)
            .limit(10)
            .get(),
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
    final d = (u.divisions.isNotEmpty ? u.divisions.first : '').trim();
    return d.isNotEmpty ? d : 'unknownDivision';
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
        _getUserCollectionRef()
            .where('codeNumber', isEqualTo: normalized)
            .limit(10)
            .get(),
        _getUserCollectionRef()
            .where('phone', isEqualTo: normalized)
            .limit(10)
            .get(),
        _getUserCollectionRef()
            .where('handle', isEqualTo: normalized)
            .limit(10)
            .get(),
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

  int _normalizeLimit(dynamic v) {
    if (v is int && v >= 0) return v;
    return 1 << 30;
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
  }) async {
    try {
      final metaSnap = await showDocRef.get();
      final meta = metaSnap.data() ?? <String, dynamic>{};
      if (!_metaNeedsCountCompute(meta, strict)) {
        return _countsFromMeta(meta);
      }

      final qSnap = await showDocRef.collection('users').get();
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
      await showDocRef.set(
        {
          'division': division,
          'area': area,
          ...counts.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return counts;
    } catch (_) {
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

    await _ensureOrSyncAccountCounts(
      showDocRef: showDocRef,
      division: division,
      area: area,
      strict: true,
    );

    try {
      await _firestore.runTransaction((tx) async {
        final rootSnap = await tx.get(userDocRef);
        final codeSnap = await tx.get(codeDocRef);
        if (rootSnap.exists) {
          throw StateError('USER_ALREADY_EXISTS:${user.id}');
        }
        if (codeSnap.exists) {
          throw StateError('CODE_NUMBER_ALREADY_EXISTS');
        }
        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};

        final activeLimit = _normalizeLimit(showData['activeLimit']);
        final totalLimit = _normalizeLimit(showData['totalLimit']);
        final counts0 = _countsFromMeta(showData);

        final existingSnap = await tx.get(showUserDocRef);
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

        tx.set(userDocRef, _toUserAccountsMap(user, isActive: wantActive));
        tx.set(
          codeDocRef,
          _userCodeReservationPayload(
            userId: user.id,
            codeNumber: normalizedCode,
            area: area,
          ),
        );
        tx.set(
          showDocRef,
          _showMetaPayload(division: division, area: area, counts: counts1),
          SetOptions(merge: true),
        );

        final userMap = _removeLegacyScheduleFields(user.toMap());
        userMap['updatedAt'] = FieldValue.serverTimestamp();
        userMap['isActive'] = wantActive;
        if (!wantActive) {
          userMap['disabledAt'] = FieldValue.serverTimestamp();
        } else {
          userMap['disabledAt'] = FieldValue.delete();
        }

        tx.set(showUserDocRef, userMap, SetOptions(merge: true));
      });
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
      await _firestore.runTransaction((tx) async {
        final existing = await tx.get(docRef);
        if (existing.exists) {
          throw StateError('해당 코드번호와 업무 지역으로 등록된 태블릿이 이미 있습니다.');
        }
        tx.set(docRef, tablet.toMap());
      });
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

  Future<void> updateUser(
    UserModel user, {
    String? previousId,
  }) async {
    final previousUserId = (previousId ?? user.id).trim();
    final nextUserId = user.id.trim();
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
      final prevSnap = await previousUserDocRef.get();
      if (prevSnap.exists && prevSnap.data() != null) {
        prevUser = UserModel.fromMap(prevSnap.id, prevSnap.data()!);
      }
    } catch (_) {}

    final newDivision = _divisionOfUser(user);
    final newArea = _areaOfUser(user);
    final newShowId = _showDocId(newDivision, newArea);
    final oldDivision = prevUser != null ? _divisionOfUser(prevUser) : newDivision;
    final oldArea = prevUser != null ? _areaOfUser(prevUser) : newArea;
    final oldShowId = _showDocId(oldDivision, oldArea);
    final identityMoved = previousUserId != nextUserId;
    final showMoved = oldShowId != newShowId;

    final newShowDocRef = _getUserShowCollectionRef().doc(newShowId);
    final newShowUserDocRef = newShowDocRef.collection('users').doc(nextUserId);
    final oldShowDocRef = _getUserShowCollectionRef().doc(oldShowId);
    final oldShowUserDocRef = oldShowDocRef.collection('users').doc(previousUserId);

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
      await _firestore.runTransaction((tx) async {
        final previousRootSnap = await tx.get(previousUserDocRef);
        if (!previousRootSnap.exists || previousRootSnap.data() == null) {
          throw StateError('USER_NOT_FOUND:$previousUserId');
        }
        final previousRootData = previousRootSnap.data()!;
        final previousCode = _rootAccountCode(previousRootData);
        final previousCodeDocRef = previousCode.isEmpty
            ? null
            : _getUserCodeCollectionRef().doc(previousCode);
        final sameCode = previousCode == nextCode;
        final nextCodeSnap = await tx.get(nextCodeDocRef);
        final previousCodeSnap = sameCode || previousCodeDocRef == null
            ? nextCodeSnap
            : await tx.get(previousCodeDocRef);
        final nextCodeOwner = (nextCodeSnap.data()?['userId'] ?? '').toString();
        if (nextCodeSnap.exists &&
            nextCodeOwner != previousUserId &&
            nextCodeOwner != nextUserId) {
          throw StateError('CODE_NUMBER_ALREADY_EXISTS');
        }
        final newShowSnap = await tx.get(newShowDocRef);
        final newShowData = newShowSnap.data() ?? <String, dynamic>{};
        final newActiveLimit = _normalizeLimit(newShowData['activeLimit']);
        final newTotalLimit = _normalizeLimit(newShowData['totalLimit']);
        final newCounts0 = _countsFromMeta(newShowData);
        final userMap = _removeLegacyScheduleFields(user.toMap());
        userMap.remove('isActive');
        userMap.remove('disabledAt');
        userMap['updatedAt'] = FieldValue.serverTimestamp();

        if (!identityMoved && !showMoved) {
          final currentShowUserSnap = await tx.get(newShowUserDocRef);
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

          tx.set(
            nextUserDocRef,
            _toUserAccountsMap(user, isActive: targetActive),
            SetOptions(merge: true),
          );
          tx.set(
            newShowDocRef,
            _showMetaPayload(
              division: newDivision,
              area: newArea,
              counts: counts1,
            ),
            SetOptions(merge: true),
          );
          tx.set(newShowUserDocRef, userMap, SetOptions(merge: true));
          tx.set(
            nextCodeDocRef,
            _userCodeReservationPayload(
              userId: nextUserId,
              codeNumber: nextCode,
              area: newArea,
              createdAt: nextCodeSnap.data()?['createdAt'],
            ),
            SetOptions(merge: true),
          );
          if (!sameCode &&
              previousCodeDocRef != null &&
              previousCodeSnap.exists &&
              (previousCodeSnap.data()?['userId'] ?? '').toString() == previousUserId) {
            tx.delete(previousCodeDocRef);
          }
          return;
        }

        if (identityMoved && !showMoved) {
          final nextRootSnap = await tx.get(nextUserDocRef);
          if (nextRootSnap.exists) {
            throw StateError('USER_ALREADY_EXISTS:$nextUserId');
          }
          final oldShowUserSnap = await tx.get(oldShowUserDocRef);
          final nextShowUserSnap = await tx.get(newShowUserDocRef);
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
          tx.set(
            nextUserDocRef,
            _toUserAccountsMap(user, isActive: targetActive),
          );
          tx.delete(previousUserDocRef);
          if (oldExists) {
            tx.delete(oldShowUserDocRef);
          }
          tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true));
          tx.set(
            newShowDocRef,
            _showMetaPayload(
              division: newDivision,
              area: newArea,
              counts: counts1,
            ),
            SetOptions(merge: true),
          );
          tx.set(
            nextCodeDocRef,
            _userCodeReservationPayload(
              userId: nextUserId,
              codeNumber: nextCode,
              area: newArea,
              createdAt: nextCodeSnap.data()?['createdAt'],
            ),
            SetOptions(merge: true),
          );
          if (!sameCode &&
              previousCodeDocRef != null &&
              previousCodeSnap.exists &&
              (previousCodeSnap.data()?['userId'] ?? '').toString() == previousUserId) {
            tx.delete(previousCodeDocRef);
          }
          return;
        }

        final oldShowSnap = await tx.get(oldShowDocRef);
        final oldShowData = oldShowSnap.data() ?? <String, dynamic>{};
        final oldCounts0 = _countsFromMeta(oldShowData);
        final oldUserSnap = await tx.get(oldShowUserDocRef);
        final newUserSnap = await tx.get(newShowUserDocRef);
        if (identityMoved) {
          final nextRootSnap = await tx.get(nextUserDocRef);
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
          tx.set(
            nextUserDocRef,
            _toUserAccountsMap(user, isActive: targetActive),
          );
          tx.delete(previousUserDocRef);
        } else {
          tx.set(
            nextUserDocRef,
            _toUserAccountsMap(user, isActive: targetActive),
            SetOptions(merge: true),
          );
        }
        if (oldExists) {
          tx.delete(oldShowUserDocRef);
        }

        final movedUserMap = <String, dynamic>{
          ...userMap,
          'isActive': targetActive,
          if (targetActive) 'disabledAt': FieldValue.delete(),
          if (!targetActive)
            'disabledAt': disabledAtValue ?? FieldValue.serverTimestamp(),
        };
        tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true));
        tx.set(
          newShowDocRef,
          _showMetaPayload(
            division: newDivision,
            area: newArea,
            counts: newCounts1,
          ),
          SetOptions(merge: true),
        );
        tx.set(
          oldShowDocRef,
          _showMetaPayload(
            division: oldDivision,
            area: oldArea,
            counts: oldCounts1,
          ),
          SetOptions(merge: true),
        );
        tx.set(
          nextCodeDocRef,
          _userCodeReservationPayload(
            userId: nextUserId,
            codeNumber: nextCode,
            area: newArea,
            createdAt: nextCodeSnap.data()?['createdAt'],
          ),
          SetOptions(merge: true),
        );
        if (!sameCode &&
            previousCodeDocRef != null &&
            previousCodeSnap.exists &&
            (previousCodeSnap.data()?['userId'] ?? '').toString() == previousUserId) {
          tx.delete(previousCodeDocRef);
        }
      });
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
      await _firestore.runTransaction((tx) async {
        if (moving) {
          final existing = await tx.get(nextRef);
          if (existing.exists) {
            throw StateError('해당 코드번호와 업무 지역으로 등록된 태블릿이 이미 있습니다.');
          }
          tx.set(nextRef, tablet.toMap());
          tx.delete(_getTabletCollectionRef().doc(previous));
          return;
        }
        tx.set(nextRef, tablet.toMap(), SetOptions(merge: true));
      });
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
      final snap = await userDocRef.get();
      if (!snap.exists || snap.data() == null) {
        throw Exception('setUserActiveStatus 실패: user_accounts 문서가 없습니다. (userId=$userId)');
      }

      final current = UserModel.fromMap(snap.id, snap.data()!);

      final division = _divisionOfUser(current);
      final area = _areaOfUser(current);
      final showId = _showDocId(division, area);

      final showDocRef = _getUserShowCollectionRef().doc(showId);
      final showUserDocRef = showDocRef.collection('users').doc(userId);

      await _ensureOrSyncAccountCounts(
        showDocRef: showDocRef,
        division: division,
        area: area,
        strict: true,
      );

      await _firestore.runTransaction((tx) async {
        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};

        final int activeLimit = _normalizeLimit(showData['activeLimit']);
        final counts0 = _countsFromMeta(showData);

        final userSnap = await tx.get(showUserDocRef);
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

        tx.set(userDocRef, rootStatusPayload, SetOptions(merge: true));

        if (currentActive == isActive) {
          tx.set(
            showUserDocRef,
            <String, dynamic>{
              ...viewStatusPayload,
              'disabledAt': isActive
                  ? FieldValue.delete()
                  : (userData['disabledAt'] ?? FieldValue.serverTimestamp()),
            },
            SetOptions(merge: true),
          );
          tx.set(
            showDocRef,
            _showMetaPayload(division: division, area: area, counts: counts0),
            SetOptions(merge: true),
          );
          return;
        }

        var activeDelta = 0;
        var inactiveDelta = 0;
        if (isActive) {
          activeDelta = 1;
          inactiveDelta = -1;
          _assertActiveLimit(counts: counts0, activeDelta: activeDelta, limit: activeLimit);

          tx.set(
            showUserDocRef,
            {
              ...viewStatusPayload,
              'disabledAt': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );
        } else {
          activeDelta = -1;
          inactiveDelta = 1;
          tx.set(
            showUserDocRef,
            {
              ...viewStatusPayload,
              'disabledAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        final counts1 = counts0.applyDeltas(
          activeDelta: activeDelta,
          inactiveDelta: inactiveDelta,
        );
        tx.set(
          showDocRef,
          _showMetaPayload(division: division, area: area, counts: counts1),
          SetOptions(merge: true),
        );
      });
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deleteUsers(List<String> ids) async {
    for (final id in ids) {
      final userDocRef = _getUserCollectionRef().doc(id);

      try {
        UserModel? prevUser;
        try {
          final snap = await userDocRef.get();
          if (snap.exists && snap.data() != null) {
            prevUser = UserModel.fromMap(snap.id, snap.data()!);
          }
        } catch (_) {}

        if (prevUser == null) {
          await userDocRef.delete();
          continue;
        }

        final division = _divisionOfUser(prevUser);
        final area = _areaOfUser(prevUser);
        final showId = _showDocId(division, area);

        final showDocRef = _getUserShowCollectionRef().doc(showId);
        final showUserDocRef = showDocRef.collection('users').doc(id);
        final normalizedCode = AccountCodeNumber.normalize(prevUser.codeNumber);
        final codeDocRef = normalizedCode.isEmpty
            ? null
            : _getUserCodeCollectionRef().doc(normalizedCode);

        await _ensureOrSyncAccountCounts(
          showDocRef: showDocRef,
          division: division,
          area: area,
          strict: true,
        );

        await _firestore.runTransaction((tx) async {
          final codeSnap = codeDocRef == null ? null : await tx.get(codeDocRef);
          if (codeSnap != null && codeSnap.exists) {
            final owner = (codeSnap.data()?['userId'] ?? '').toString();
            if (owner.isNotEmpty && owner != id) {
              throw StateError('USER_CODE_RESERVATION_MISMATCH:$normalizedCode');
            }
          }
          final showSnap = await tx.get(showDocRef);
          final showData = showSnap.data() ?? <String, dynamic>{};
          final counts0 = _countsFromMeta(showData);

          final showUserSnap = await tx.get(showUserDocRef);
          var counts1 = counts0;
          if (showUserSnap.exists) {
            final d = showUserSnap.data() ?? <String, dynamic>{};
            final wasActive = (d['isActive'] as bool?) ?? false;
            counts1 = counts0.applyDeltas(
              activeDelta: wasActive ? -1 : 0,
              inactiveDelta: wasActive ? 0 : -1,
            );
          }

          tx.delete(showUserDocRef);
          tx.delete(userDocRef);
          if (codeDocRef != null && codeSnap != null && codeSnap.exists) {
            tx.delete(codeDocRef);
          }
          tx.set(
            showDocRef,
            _showMetaPayload(division: division, area: area, counts: counts1),
            SetOptions(merge: true),
          );
        });

      } on FirebaseException {
        rethrow;
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> deleteTablets(List<String> ids) async {
    for (final id in ids) {
      final docRef = _getTabletCollectionRef().doc(id);
      try {
        await docRef.delete();

      } on FirebaseException {
        rethrow;
      } catch (_) {
        rethrow;
      }
    }
  }
}
