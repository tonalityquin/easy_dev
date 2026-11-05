import '../../../../app/diagnostics/firebase_activity_meter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../features/account/domain/models/user/user_model.dart';
import '../../../../features/account/domain/models/user/user_account_view_projection.dart';
import '../../../../features/account/data/services/user_account_show_map.dart';
import '../../../../app/models/account_role_diagnostics.dart';
import '../../../auth/account_code_number.dart';

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
    return UserAccountViewProjection.fromUser(user);
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
        _users.where('codeNumber', isEqualTo: normalized).limit(10).get().trackFirestore('GET', 'shared/secondary/data/services/dev_user_write_service.dart'),
        _users.where('phone', isEqualTo: normalized).limit(10).get().trackFirestore('GET', 'shared/secondary/data/services/dev_user_write_service.dart'),
        _users.where('handle', isEqualTo: normalized).limit(10).get().trackFirestore('GET', 'shared/secondary/data/services/dev_user_write_service.dart'),
      ],
    );
    final duplicated = snapshots
        .expand((snapshot) => snapshot.docs)
        .any((doc) => !excludeDocumentIds.contains(doc.id));
    if (duplicated) {
      throw StateError('CODE_NUMBER_ALREADY_EXISTS');
    }
  }

  Future<void> createUser({
    required UserModel user,
    required String division,
    required String area,
    void Function(String message)? log,
  }) async {
    final code = AccountCodeNumber.normalize(user.codeNumber);
    if (!AccountCodeNumber.isValid(code)) throw StateError('INVALID_CODE_NUMBER');
    final company = division.trim();
    final region = area.trim();
    final showId = _showId(company, region);
    final rootRef = _users.doc(user.id);
    final codeRef = _codes.doc(code);
    final viewRef = _shows.doc(showId);
    log?.call('DevUserWriteService create 시작: map=true counts=disabled');
    final codeSnap = await codeRef.get(
      const GetOptions(source: Source.server),
    ).trackFirestore('GET', 'shared/secondary/data/services/dev_user_write_service.dart');
    if (codeSnap.exists) throw StateError('CODE_NUMBER_ALREADY_EXISTS');
    final rootSnap = await rootRef.get(
      const GetOptions(source: Source.server),
    ).trackFirestore('GET', 'shared/secondary/data/services/dev_user_write_service.dart');
    if (rootSnap.exists) throw StateError('USER_ALREADY_EXISTS');
    final rootMap = <String, dynamic>{
      ..._rootPayload(user),
      'isActive': user.isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final viewMap = <String, dynamic>{
      ..._projectionPayload(user),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!user.isActive) 'disabledAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.trackedActivityBatch(
      'shared/secondary/data/services/dev_user_write_service.dart',
    );
    batch.set(rootRef, rootMap);
    batch.set(codeRef, _reservationPayload(
      userId: user.id,
      codeNumber: code,
      area: region,
    ));
    batch.set(
      viewRef,
      UserAccountShowMap.putPayload(user.id, viewMap),
      UserAccountShowMap.putOptions(user.id),
    );
    AccountRoleDiagnostics.record('dev_user_create_batch_start writes=3 view=map');
    await batch.commit();
    AccountRoleDiagnostics.record('dev_user_create_batch_committed writes=3 view=map');
    log?.call('DevUserWriteService create 완료: map=true writes=3');
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
    final oldId = previousUserId.trim();
    final newId = user.id.trim();
    final newCode = AccountCodeNumber.normalize(user.codeNumber);
    if (!AccountCodeNumber.isValid(newCode)) throw StateError('INVALID_CODE_NUMBER');
    await _assertUniqueUserCodeNumber(
      newCode, excludeDocumentIds: <String>{oldId, newId},
    );
    final oldRootRef = _users.doc(oldId);
    final newRootRef = _users.doc(newId);
    final oldViewRef = _shows.doc(_showId(previousDivision, previousArea));
    final newViewRef = _shows.doc(_showId(targetDivision, targetArea));
    final oldLegacyRef = oldViewRef.collection('users').doc(oldId);
    final newLegacyRef = newViewRef.collection('users').doc(newId);
    AccountRoleDiagnostics.record('dev_user_update_start view=map counts=disabled');
    await _firestore.runTrackedActivityTransaction((tx) async {
      final oldRootSnap = await tx.get(oldRootRef).trackFirestore(
        'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
      );
      if (!oldRootSnap.exists || oldRootSnap.data() == null) {
        throw StateError('USER_NOT_FOUND:$oldId');
      }
      final oldData = oldRootSnap.data()!;
      final oldCode = _rootAccountCode(oldData);
      final newCodeRef = _codes.doc(newCode);
      final oldCodeRef = oldCode.isEmpty ? null : _codes.doc(oldCode);
      final newCodeSnap = await tx.get(newCodeRef).trackFirestore(
        'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
      );
      final oldCodeSnap = oldCodeRef == null || oldCode == newCode
          ? newCodeSnap
          : await tx.get(oldCodeRef).trackFirestore(
              'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
            );
      final codeOwner = (newCodeSnap.data()?['userId'] ?? '').toString();
      if (newCodeSnap.exists && codeOwner != oldId && codeOwner != newId) {
        throw StateError('CODE_NUMBER_ALREADY_EXISTS');
      }
      if (oldId != newId) {
        final newRootSnap = await tx.get(newRootRef).trackFirestore(
          'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
        );
        if (newRootSnap.exists) throw StateError('USER_ALREADY_EXISTS:$newId');
      }
      final oldViewSnap = await tx.get(oldViewRef).trackFirestore(
        'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
      );
      final oldLegacySnap = await tx.get(oldLegacyRef).trackFirestore(
        'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
      );
      final moved = oldViewRef.path != newViewRef.path || oldId != newId;
      final newViewSnap = oldViewRef.path == newViewRef.path
          ? oldViewSnap
          : await tx.get(newViewRef).trackFirestore(
              'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
            );
      if (moved) {
        if (UserAccountShowMap.account(newViewSnap.data(), newId) != null) {
          throw StateError('SHOW_USER_ALREADY_EXISTS:$newId');
        }
        final newLegacySnap = await tx.get(newLegacyRef).trackFirestore(
          'GET', 'shared/secondary/data/services/dev_user_write_service.dart',
        );
        if (newLegacySnap.exists && newLegacyRef.path != oldLegacyRef.path) {
          throw StateError('SHOW_USER_ALREADY_EXISTS:$newId');
        }
      }
      final active = (oldData['isActive'] as bool?) ?? user.isActive;
      final rootMap = <String, dynamic>{
        ..._rootPayload(user),
        'isActive': active,
        'createdAt': oldData['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final previous = UserAccountShowMap.account(oldViewSnap.data(), oldId) ??
          oldLegacySnap.data();
      final summary = <String, dynamic>{
        ..._projectionPayload(user),
        'isActive': active,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!active)
          'disabledAt': previous?['disabledAt'] ?? FieldValue.serverTimestamp(),
      };
      if (oldId == newId) {
        tx.set(newRootRef, rootMap, SetOptions(merge: true));
      } else {
        tx.set(newRootRef, rootMap);
        tx.delete(oldRootRef);
      }
      if (moved && oldViewRef.path == newViewRef.path &&
          UserAccountShowMap.account(oldViewSnap.data(), oldId) != null) {
        tx.set(
          newViewRef,
          UserAccountShowMap.movePayload(oldId, newId, summary),
          UserAccountShowMap.moveOptions(oldId, newId),
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
          UserAccountShowMap.putPayload(newId, summary),
          UserAccountShowMap.putOptions(newId),
        );
      }
      if (oldLegacySnap.exists) tx.delete(oldLegacyRef);
      tx.set(newCodeRef, _reservationPayload(
        userId: newId,
        codeNumber: newCode,
        area: targetArea.trim(),
        createdAt: newCodeSnap.data()?['createdAt'],
      ), SetOptions(merge: true));
      if (oldCodeRef != null && oldCode != newCode && oldCodeSnap.exists &&
          (oldCodeSnap.data()?['userId'] ?? '').toString() == oldId) {
        tx.delete(oldCodeRef);
      }
    }).trackFirestore('TRANSACTION', 'shared/secondary/data/services/dev_user_write_service.dart');
    AccountRoleDiagnostics.record('dev_user_update_committed view=map counts=disabled');
    log?.call('DevUserWriteService update 완료: view=map');
  }
}
