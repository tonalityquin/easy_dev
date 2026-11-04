import '../../../../app/diagnostics/firebase_activity_meter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'user_account_show_map.dart';

typedef UserActiveStateBackfillLogger = void Function(
  String message,
  double progress,
);

class UserActiveStateBackfillResult {
  const UserActiveStateBackfillResult({
    required this.rootTotal,
    required this.viewTotal,
    required this.updatedRoots,
    required this.alreadyMatchedRoots,
    required this.viewPasswordsRemoved,
    required this.duplicateViews,
    required this.conflictingViews,
    required this.viewStateMissing,
    required this.orphanViews,
    required this.rootWithoutView,
    required this.failedWrites,
    required this.verificationMismatches,
  });

  final int rootTotal;
  final int viewTotal;
  final int updatedRoots;
  final int alreadyMatchedRoots;
  final int viewPasswordsRemoved;
  final int duplicateViews;
  final int conflictingViews;
  final int viewStateMissing;
  final int orphanViews;
  final int rootWithoutView;
  final int failedWrites;
  final int verificationMismatches;

  bool get hasBlockingIssues =>
      conflictingViews > 0 ||
      viewStateMissing > 0 ||
      orphanViews > 0 ||
      rootWithoutView > 0 ||
      failedWrites > 0 ||
      verificationMismatches > 0;

  String get summary =>
      'Root $rootTotal개 · View $viewTotal개 · Root 갱신 $updatedRoots개 · 이미 일치 $alreadyMatchedRoots개 · View password 제거 $viewPasswordsRemoved개 · 중복 View $duplicateViews개 · 충돌 View $conflictingViews개 · View isActive 누락 $viewStateMissing개 · 고아 View $orphanViews개 · View 없는 Root $rootWithoutView개 · 쓰기 실패 $failedWrites개 · 검증 불일치 $verificationMismatches개';
}

class UserActiveStateBackfillService {
  UserActiveStateBackfillService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int _batchLimit = 400;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _rootUsers =>
      _firestore.collection('user_accounts');

  CollectionReference<Map<String, dynamic>> get _viewRoots =>
      _firestore.collection('user_accounts_show');

  Future<UserActiveStateBackfillResult> run({
    UserActiveStateBackfillLogger? onLog,
  }) async {
    onLog?.call('user_accounts_show 계정 상태 수집을 시작합니다.', 0.02);

    final viewRootSnapshot = await _viewRoots.get(
      const GetOptions(source: Source.server),
    ).trackFirestore('GET', 'features/account/data/services/user_active_state_backfill_service.dart');
    final activeByUserId = <String, bool>{};
    final conflictIds = <String>{};
    final viewIds = <String>{};
    final passwordRefs = <DocumentReference<Map<String, dynamic>>>[];
    final mapPasswords = <MapEntry<DocumentReference<Map<String, dynamic>>, String>>[];
    var viewTotal = 0;
    var duplicateViews = 0;
    var viewStateMissing = 0;

    void registerView(String id, Map<String, dynamic> data) {
      viewTotal += 1;
      viewIds.add(id);
      final active = data['isActive'];
      if (active is! bool) {
        viewStateMissing += 1;
        return;
      }
      final previous = activeByUserId[id];
      if (previous == null) {
        activeByUserId[id] = active;
      } else {
        duplicateViews += 1;
        if (previous != active) conflictIds.add(id);
      }
    }

    for (var index = 0; index < viewRootSnapshot.docs.length; index += 1) {
      final parent = viewRootSnapshot.docs[index];
      final mapEntries = UserAccountShowMap.entries(parent.data());
      final mapIds = <String>{};
      for (final entry in mapEntries) {
        mapIds.add(entry.key);
        registerView(entry.key, entry.value);
        if (entry.value.containsKey('password')) {
          mapPasswords.add(MapEntry(parent.reference, entry.key));
        }
      }
      if (!UserAccountShowMap.isComplete(parent.data())) {
        final legacy = await parent.reference.collection('users').get(
          const GetOptions(source: Source.server),
        ).trackFirestore('GET', 'features/account/data/services/user_active_state_backfill_service.dart');
        for (final doc in legacy.docs) {
          if (doc.data().containsKey('password')) passwordRefs.add(doc.reference);
          if (!mapIds.contains(doc.id)) registerView(doc.id, doc.data());
        }
      }
      final progress = viewRootSnapshot.docs.isEmpty
          ? 0.2
          : 0.04 + ((index + 1) / viewRootSnapshot.docs.length) * 0.16;
      onLog?.call(
        'View 스캔 진행: ${index + 1}/${viewRootSnapshot.docs.length}',
        progress,
      );
    }

    for (final conflictId in conflictIds) {
      activeByUserId.remove(conflictId);
    }

    onLog?.call(
      'View 스캔 완료: 계정 $viewTotal개, 상태 충돌 ${conflictIds.length}개, 상태 누락 $viewStateMissing개',
      0.22,
    );

    var failedWrites = 0;
    var viewPasswordsRemoved = 0;
    if (passwordRefs.isNotEmpty) {
      for (var offset = 0; offset < passwordRefs.length; offset += _batchLimit) {
        final end = offset + _batchLimit < passwordRefs.length
            ? offset + _batchLimit
            : passwordRefs.length;
        final batch = _firestore.trackedActivityBatch('features/account/data/services/user_active_state_backfill_service.dart');
        for (final reference in passwordRefs.sublist(offset, end)) {
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/account/data/services/user_active_state_backfill_service.dart', result: 'staged');
          batch.set(
            reference,
            <String, dynamic>{'password': FieldValue.delete()},
            SetOptions(merge: true),
          );
        }
        try {
          await batch.commit().trackFirestore('BATCH', 'features/account/data/services/user_active_state_backfill_service.dart');
          viewPasswordsRemoved += end - offset;
        } on FirebaseException catch (error) {
          failedWrites += end - offset;
          debugPrint(
            'user_accounts_show password 정리 실패 code=${error.code} count=${end - offset}',
          );
        }
        onLog?.call(
          'View password 정리: $viewPasswordsRemoved/${passwordRefs.length}',
          0.22 + (end / passwordRefs.length) * 0.08,
        );
      }
    }

    if (mapPasswords.isNotEmpty) {
      for (var offset = 0; offset < mapPasswords.length; offset += _batchLimit) {
        final end = offset + _batchLimit < mapPasswords.length
            ? offset + _batchLimit
            : mapPasswords.length;
        final batch = _firestore.trackedActivityBatch(
          'features/account/data/services/user_active_state_backfill_service.dart',
        );
        for (final item in mapPasswords.sublist(offset, end)) {
          batch.update(item.key, <Object, Object?>{
            FieldPath(<String>['users', item.value, 'password']):
                FieldValue.delete(),
          });
        }
        try {
          await batch.commit().trackFirestore(
            'BATCH',
            'features/account/data/services/user_active_state_backfill_service.dart',
          );
          viewPasswordsRemoved += end - offset;
        } on FirebaseException catch (error) {
          failedWrites += end - offset;
          debugPrint('user_accounts_show Map password 정리 실패 code=${error.code}');
        }
      }
    }

    onLog?.call('user_accounts 원본 계정 조회를 시작합니다.', 0.32);
    final rootSnapshot = await _rootUsers.get(
      const GetOptions(source: Source.server),
    ).trackFirestore('GET', 'features/account/data/services/user_active_state_backfill_service.dart');
    final rootIds = rootSnapshot.docs.map((doc) => doc.id).toSet();
    final orphanViews = viewIds.difference(rootIds).length;
    final rootWithoutView = rootIds.difference(viewIds).length;
    final pendingUpdates = <MapEntry<DocumentReference<Map<String, dynamic>>, bool>>[];
    var alreadyMatchedRoots = 0;

    for (final rootDoc in rootSnapshot.docs) {
      final active = activeByUserId[rootDoc.id];
      if (active == null) continue;
      final existing = rootDoc.data()['isActive'];
      if (existing is bool && existing == active) {
        alreadyMatchedRoots += 1;
        continue;
      }
      pendingUpdates.add(MapEntry(rootDoc.reference, active));
    }

    var updatedRoots = 0;
    if (pendingUpdates.isNotEmpty) {
      for (var offset = 0; offset < pendingUpdates.length; offset += _batchLimit) {
        final end = offset + _batchLimit < pendingUpdates.length
            ? offset + _batchLimit
            : pendingUpdates.length;
        final batch = _firestore.trackedActivityBatch('features/account/data/services/user_active_state_backfill_service.dart');
        for (final entry in pendingUpdates.sublist(offset, end)) {
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/account/data/services/user_active_state_backfill_service.dart', result: 'staged');
          batch.set(
            entry.key,
            <String, dynamic>{
              'isActive': entry.value,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        try {
          await batch.commit().trackFirestore('BATCH', 'features/account/data/services/user_active_state_backfill_service.dart');
          updatedRoots += end - offset;
        } on FirebaseException catch (error) {
          failedWrites += end - offset;
          debugPrint(
            'user_accounts isActive backfill 실패 code=${error.code} count=${end - offset}',
          );
        }
        onLog?.call(
          'Root isActive 반영: $updatedRoots/${pendingUpdates.length}',
          0.36 + (end / pendingUpdates.length) * 0.38,
        );
      }
    }

    onLog?.call('Root/View isActive 일치 여부를 재검증합니다.', 0.78);
    final verifySnapshot = await _rootUsers.get(
      const GetOptions(source: Source.server),
    ).trackFirestore('GET', 'features/account/data/services/user_active_state_backfill_service.dart');
    var verificationMismatches = 0;
    for (final rootDoc in verifySnapshot.docs) {
      final expected = activeByUserId[rootDoc.id];
      if (expected == null) continue;
      if (rootDoc.data()['isActive'] != expected) {
        verificationMismatches += 1;
      }
    }

    final result = UserActiveStateBackfillResult(
      rootTotal: rootSnapshot.docs.length,
      viewTotal: viewTotal,
      updatedRoots: updatedRoots,
      alreadyMatchedRoots: alreadyMatchedRoots,
      viewPasswordsRemoved: viewPasswordsRemoved,
      duplicateViews: duplicateViews,
      conflictingViews: conflictIds.length,
      viewStateMissing: viewStateMissing,
      orphanViews: orphanViews,
      rootWithoutView: rootWithoutView,
      failedWrites: failedWrites,
      verificationMismatches: verificationMismatches,
    );

    onLog?.call('isActive backfill 검증 완료: ${result.summary}', 1);
    return result;
  }
}
