import '../../../../app/diagnostics/firebase_activity_meter.dart';
import '../../../../app/models/account_role_diagnostics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../shared/auth/account_code_number.dart';
import '../../applications/tablet_account_diagnostics.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';
import '../../domain/models/user/user_account_view_projection.dart';
import 'user_account_show_map.dart';

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
            .get().trackFirestore('QUERY', 'features/account/data/services/user_write_service.dart', collection: 'tablet_accounts', pathTemplate: 'tablet_accounts'),
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
            .get().trackFirestore('QUERY', 'features/account/data/services/user_write_service.dart', collection: 'user_accounts', pathTemplate: 'user_accounts'),
        _getUserCollectionRef()
            .where('phone', isEqualTo: normalized)
            .limit(10)
            .get().trackFirestore('QUERY', 'features/account/data/services/user_write_service.dart', collection: 'user_accounts', pathTemplate: 'user_accounts'),
        _getUserCollectionRef()
            .where('handle', isEqualTo: normalized)
            .limit(10)
            .get().trackFirestore('QUERY', 'features/account/data/services/user_write_service.dart', collection: 'user_accounts', pathTemplate: 'user_accounts'),
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

  Future<void> addUserCard(UserModel user) async {
    final code = AccountCodeNumber.normalize(user.codeNumber);
    if (!AccountCodeNumber.isValid(code)) {
      throw StateError('INVALID_CODE_NUMBER');
    }
    final division = _divisionOfUser(user);
    final area = _areaOfUser(user);
    final expectedId = AccountCodeNumber.documentId(codeNumber: code, area: area);
    if (expectedId.isEmpty || user.id.trim() != expectedId) {
      throw StateError('INVALID_USER_DOCUMENT_ID');
    }
    final rootRef = _getUserCollectionRef().doc(user.id);
    final codeRef = _getUserCodeCollectionRef().doc(code);
    final viewRef = _getUserShowCollectionRef()
        .doc(_showDocId(division, area));
    AccountRoleDiagnostics.recordCreation('user_create_start strategy=single_code_read_three_write_batch');
    try {
      final reserved = await codeRef.get(
        const GetOptions(source: Source.server),
      ).trackFirestore('GET', 'features/account/data/services/user_write_service.dart', collection: 'user_account_codes', pathTemplate: 'user_account_codes/*', readPurpose: 'USER_CREATE_CODE_DUPLICATE_CHECK');
      if (reserved.exists) {
        AccountRoleDiagnostics.recordCreation('user_create_rejected reason=duplicate_code');
        throw StateError('CODE_NUMBER_ALREADY_EXISTS');
      }
      AccountRoleDiagnostics.recordCreation('user_create_code_check reads=1 duplicate=false');
      final view = <String, dynamic>{
        ...UserAccountViewProjection.fromUser(user),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!user.isActive) 'disabledAt': FieldValue.serverTimestamp(),
      };
      final batch = _firestore.trackedActivityBatch(
        'features/account/data/services/user_write_service.dart',
      );
      batch.set(rootRef, _toUserAccountsMap(user));
      batch.set(codeRef, _userCodeReservationPayload(
        userId: user.id,
        codeNumber: code,
        area: area,
      ));
      batch.set(
        viewRef,
        UserAccountShowMap.putPayload(user.id, view),
        UserAccountShowMap.putOptions(user.id),
      );
      AccountRoleDiagnostics.recordCreation('user_create_batch_start writes=3 view=map createPolicy=projection_only');
      await batch.commit();
      AccountRoleDiagnostics.recordCreation('user_create_batch_committed writes=3 view=map');
    } catch (error) {
      AccountRoleDiagnostics.recordCreation(
        'user_create_failed type=${error.runtimeType} reason=${_createFailureCategory(error)}',
      );
      rethrow;
    }
  }

  String _createFailureCategory(Object error) {
    final message = error.toString();
    if (message.contains('CODE_NUMBER_ALREADY_EXISTS')) return 'duplicate_code';
    if (message.contains('INVALID_CODE_NUMBER') ||
        message.contains('INVALID_USER_DOCUMENT_ID')) return 'invalid_identity';
    if (error is FirebaseException) return 'firestore_${error.code}';
    return 'unknown';
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
      await _firestore.runTrackedActivityTransaction((tx) async {
        final existing = await tx.get(docRef).trackFirestore('GET', 'features/account/data/services/user_write_service.dart', collection: 'tablet_accounts', pathTemplate: 'tablet_accounts/*', readPurpose: 'TABLET_CREATE_EXISTENCE_CHECK');
        if (existing.exists) {
          throw StateError('해당 코드번호와 업무 지역으로 등록된 태블릿이 이미 있습니다.');
        }
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/account/data/services/user_write_service.dart', result: 'staged');
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
    final oldId = (previousId ?? user.id).trim();
    final nextId = user.id.trim();
    final nextCode = AccountCodeNumber.normalize(user.codeNumber);
    if (!AccountCodeNumber.isValid(nextCode)) {
      throw StateError('INVALID_CODE_NUMBER');
    }
    await _assertUniqueUserCodeNumber(
      nextCode,
      excludeDocumentIds: <String>{oldId, nextId},
    );
    final oldRootRef = _getUserCollectionRef().doc(oldId);
    final newRootRef = _getUserCollectionRef().doc(nextId);
    final newArea = _areaOfUser(user);
    final newViewRef = _getUserShowCollectionRef()
        .doc(_showDocId(_divisionOfUser(user), newArea));
    final newCodeRef = _getUserCodeCollectionRef().doc(nextCode);
    AccountRoleDiagnostics.record('user_update_start view=map counts=disabled');
    await _firestore.runTrackedActivityTransaction((tx) async {
      final oldRootSnap = await tx.get(oldRootRef).trackFirestore(
        'GET', 'features/account/data/services/user_write_service.dart',
      collection: 'user_accounts', pathTemplate: 'user_accounts/*', readPurpose: 'USER_UPDATE_SOURCE_ACCOUNT_VALIDATION');
      if (!oldRootSnap.exists || oldRootSnap.data() == null) {
        throw StateError('USER_NOT_FOUND:$oldId');
      }
      final oldData = oldRootSnap.data()!;
      final oldUser = UserModel.fromMap(oldId, oldData);
      final oldViewRef = _getUserShowCollectionRef().doc(
        _showDocId(_divisionOfUser(oldUser), _areaOfUser(oldUser)),
      );
      final oldCode = _rootAccountCode(oldData);
      final oldCodeRef = oldCode.isEmpty
          ? null
          : _getUserCodeCollectionRef().doc(oldCode);
      final nextCodeSnap = await tx.get(newCodeRef).trackFirestore(
        'GET', 'features/account/data/services/user_write_service.dart',
      collection: 'user_account_codes', pathTemplate: 'user_account_codes/*', readPurpose: 'USER_UPDATE_NEXT_CODE_RESERVATION_CHECK');
      final previousCodeSnap = oldCodeRef == null || oldCode == nextCode
          ? nextCodeSnap
          : await tx.get(oldCodeRef).trackFirestore(
              'GET', 'features/account/data/services/user_write_service.dart',
            collection: 'user_account_codes', pathTemplate: 'user_account_codes/*', readPurpose: 'USER_UPDATE_PREVIOUS_CODE_RESERVATION_CHECK');
      final owner = (nextCodeSnap.data()?['userId'] ?? '').toString();
      if (nextCodeSnap.exists && owner != oldId && owner != nextId) {
        throw StateError('CODE_NUMBER_ALREADY_EXISTS');
      }
      final oldViewSnap = await tx.get(oldViewRef).trackFirestore(
        'GET', 'features/account/data/services/user_write_service.dart',
      collection: 'user_accounts_show', pathTemplate: 'user_accounts_show/*', readPurpose: 'USER_UPDATE_OLD_PROJECTION_VALIDATION');
      final moved = oldViewRef.path != newViewRef.path || oldId != nextId;
      final newViewSnap = oldViewRef.path == newViewRef.path
          ? oldViewSnap
          : await tx.get(newViewRef).trackFirestore(
              'GET', 'features/account/data/services/user_write_service.dart',
            collection: 'user_accounts_show', pathTemplate: 'user_accounts_show/*', readPurpose: 'USER_UPDATE_NEW_PROJECTION_CONFLICT_CHECK');
      if (oldId != nextId) {
        final newRootSnap = await tx.get(newRootRef).trackFirestore(
          'GET', 'features/account/data/services/user_write_service.dart',
        collection: 'user_accounts', pathTemplate: 'user_accounts/*', readPurpose: 'USER_UPDATE_TARGET_ROOT_CONFLICT_CHECK');
        if (newRootSnap.exists) throw StateError('USER_ALREADY_EXISTS:$nextId');
      }
      if (moved) {
        if (UserAccountShowMap.account(newViewSnap.data(), nextId) != null) {
          throw StateError('SHOW_USER_ALREADY_EXISTS:$nextId');
        }
      }
      final existingActive = (oldData['isActive'] as bool?) ?? user.isActive;
      final rootData = _toUserAccountsMap(user, isActive: existingActive);
      if (oldData.containsKey('createdAt')) {
        rootData['createdAt'] = oldData['createdAt'];
      }
      final formerView = UserAccountShowMap.account(oldViewSnap.data(), oldId);
      if (formerView == null) throw StateError('SHOW_USER_DOC_MISSING:$oldId');
      final summary = <String, dynamic>{
        ...UserAccountViewProjection.fromUser(user),
        'isActive': existingActive,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!existingActive)
          'disabledAt': formerView['disabledAt'] ?? FieldValue.serverTimestamp(),
      };
      if (oldId == nextId) {
        tx.set(newRootRef, rootData, SetOptions(merge: true));
      } else {
        tx.set(newRootRef, rootData);
        tx.delete(oldRootRef);
      }
      if (moved && oldViewRef.path == newViewRef.path &&
          UserAccountShowMap.account(oldViewSnap.data(), oldId) != null) {
        tx.set(
          newViewRef,
          UserAccountShowMap.movePayload(oldId, nextId, summary),
          UserAccountShowMap.moveOptions(oldId, nextId),
        );
      } else {
        if (moved &&
            UserAccountShowMap.account(oldViewSnap.data(), oldId) != null) {
          tx.set(
            oldViewRef,
            UserAccountShowMap.deletePayload(oldId),
            UserAccountShowMap.deleteOptions(oldId),
          );
        }
        tx.set(
          newViewRef,
          UserAccountShowMap.putPayload(nextId, summary),
          UserAccountShowMap.putOptions(nextId),
        );
      }
      tx.set(newCodeRef, _userCodeReservationPayload(
        userId: nextId,
        codeNumber: nextCode,
        area: newArea,
        createdAt: nextCodeSnap.data()?['createdAt'],
      ), SetOptions(merge: true));
      if (oldCodeRef != null && oldCode != nextCode &&
          previousCodeSnap.exists &&
          (previousCodeSnap.data()?['userId'] ?? '').toString() == oldId) {
        tx.delete(oldCodeRef);
      }
    });
    AccountRoleDiagnostics.record('user_update_committed view=map counts=disabled');
    AccountRoleDiagnostics.recordList('user_update_committed view=map_only legacyViewReads=0');
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
      await _firestore.runTrackedActivityTransaction((tx) async {
        if (moving) {
          final existing = await tx.get(nextRef).trackFirestore('GET', 'features/account/data/services/user_write_service.dart', collection: 'tablet_accounts', pathTemplate: 'tablet_accounts/*', readPurpose: 'TABLET_MOVE_TARGET_DUPLICATE_CHECK');
          if (existing.exists) {
            throw StateError('해당 코드번호와 업무 지역으로 등록된 태블릿이 이미 있습니다.');
          }
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/account/data/services/user_write_service.dart', result: 'staged');
          tx.set(nextRef, tablet.toMap());
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_DELETE', source: 'features/account/data/services/user_write_service.dart', result: 'staged');
          tx.delete(_getTabletCollectionRef().doc(previous));
          return;
        }
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/account/data/services/user_write_service.dart', result: 'staged');
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
    final rootRef = _getUserCollectionRef().doc(userId);
    final rootSnap = await rootRef.get().trackFirestore(
      'GET', 'features/account/data/services/user_write_service.dart',
    collection: 'user_accounts', pathTemplate: 'user_accounts/*', readPurpose: 'USER_ACTIVE_ROOT_VALIDATION');
    if (!rootSnap.exists || rootSnap.data() == null) {
      throw StateError('USER_NOT_FOUND:$userId');
    }
    final user = UserModel.fromMap(rootSnap.id, rootSnap.data()!);
    final viewRef = _getUserShowCollectionRef()
        .doc(_showDocId(_divisionOfUser(user), _areaOfUser(user)));
    final viewSnap = await viewRef.get().trackFirestore(
      'GET', 'features/account/data/services/user_write_service.dart',
    collection: 'user_accounts_show', pathTemplate: 'user_accounts_show/*', readPurpose: 'USER_ACTIVE_PROJECTION_VALIDATION');
    final existing = UserAccountShowMap.account(viewSnap.data(), userId);
    if (existing == null) throw StateError('SHOW_USER_DOC_MISSING:$userId');
    final rootPayload = <String, dynamic>{
      ..._weekdayScheduleMigrationPayload(user),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.trackedActivityBatch(
      'features/account/data/services/user_write_service.dart',
    );
    batch.set(rootRef, rootPayload, SetOptions(merge: true));
    batch.set(
      viewRef,
      UserAccountShowMap.statusPayload(userId, isActive, existing['disabledAt']),
      UserAccountShowMap.statusOptions(userId),
    );
    AccountRoleDiagnostics.record('user_active_batch_start view=map counts=disabled');
    await batch.commit();
    AccountRoleDiagnostics.record('user_active_batch_committed view=map');
    AccountRoleDiagnostics.recordList('user_active_committed view=map_only legacyViewReads=0');
  }

  Future<void> deleteUsers(List<String> ids) async {
    for (final id in ids) {
      final rootRef = _getUserCollectionRef().doc(id);
      final rootSnap = await rootRef.get().trackFirestore(
        'GET', 'features/account/data/services/user_write_service.dart',
      collection: 'user_accounts', pathTemplate: 'user_accounts/*', readPurpose: 'USER_DELETE_ROOT_VALIDATION');
      if (!rootSnap.exists || rootSnap.data() == null) continue;
      final user = UserModel.fromMap(rootSnap.id, rootSnap.data()!);
      final viewRef = _getUserShowCollectionRef()
          .doc(_showDocId(_divisionOfUser(user), _areaOfUser(user)));
      final viewSnap = await viewRef.get().trackFirestore(
        'GET', 'features/account/data/services/user_write_service.dart',
      collection: 'user_accounts_show', pathTemplate: 'user_accounts_show/*', readPurpose: 'USER_DELETE_PROJECTION_VALIDATION');
      final existing = UserAccountShowMap.account(viewSnap.data(), id);
      if (existing == null) throw StateError('SHOW_USER_DOC_MISSING:$id');
      final code = AccountCodeNumber.normalize(user.codeNumber);
      final codeRef = code.isEmpty ? null : _getUserCodeCollectionRef().doc(code);
      final codeSnap = codeRef == null ? null : await codeRef.get(
        const GetOptions(source: Source.server),
      ).trackFirestore('GET', 'features/account/data/services/user_write_service.dart', collection: 'user_account_codes', pathTemplate: 'user_account_codes/*', readPurpose: 'USER_DELETE_CODE_RESERVATION_VALIDATION');
      if (codeSnap != null && codeSnap.exists &&
          (codeSnap.data()?['userId'] ?? '').toString() != id) {
        throw StateError('USER_CODE_RESERVATION_MISMATCH');
      }
      final batch = _firestore.trackedActivityBatch(
        'features/account/data/services/user_write_service.dart',
      );
      batch.set(
        viewRef,
        UserAccountShowMap.deletePayload(id),
        UserAccountShowMap.deleteOptions(id),
      );
      batch.delete(rootRef);
      if (codeRef != null && codeSnap != null && codeSnap.exists) {
        batch.delete(codeRef);
      }
      AccountRoleDiagnostics.record('user_delete_batch_start view=map counts=disabled');
      await batch.commit();
      AccountRoleDiagnostics.record('user_delete_batch_committed view=map counts=disabled');
      AccountRoleDiagnostics.recordList('user_delete_committed view=map_only legacyViewReads=0');
    }
  }

  Future<void> deleteTablets(List<String> ids) async {
    for (final id in ids) {
      final docRef = _getTabletCollectionRef().doc(id);
      try {
        await docRef.delete().trackFirestore('DELETE', 'features/account/data/services/user_write_service.dart', collection: 'tablet_accounts', pathTemplate: 'tablet_accounts/*');

      } on FirebaseException {
        rethrow;
      } catch (_) {
        rethrow;
      }
    }
  }
}
