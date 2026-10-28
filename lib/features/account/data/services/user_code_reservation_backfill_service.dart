import '../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../shared/auth/account_code_number.dart';

typedef UserCodeReservationBackfillLogger = void Function(
  String message,
  double progress,
);

class UserCodeReservationBackfillResult {
  const UserCodeReservationBackfillResult({
    required this.rootTotal,
    required this.reservationTotal,
    required this.createdReservations,
    required this.alreadyMatchedReservations,
    required this.invalidRootCodes,
    required this.duplicateCodes,
    required this.reservationConflicts,
    required this.orphanReservations,
    required this.failedWrites,
    required this.verificationMismatches,
  });

  final int rootTotal;
  final int reservationTotal;
  final int createdReservations;
  final int alreadyMatchedReservations;
  final int invalidRootCodes;
  final int duplicateCodes;
  final int reservationConflicts;
  final int orphanReservations;
  final int failedWrites;
  final int verificationMismatches;

  bool get hasBlockingIssues =>
      invalidRootCodes > 0 ||
      duplicateCodes > 0 ||
      reservationConflicts > 0 ||
      orphanReservations > 0 ||
      failedWrites > 0 ||
      verificationMismatches > 0;

  String get summary =>
      'Root $rootTotal개 · 인덱스 $reservationTotal개 · 신규 인덱스 $createdReservations개 · 이미 일치 $alreadyMatchedReservations개 · 유효하지 않은 코드 $invalidRootCodes개 · 중복 코드 $duplicateCodes개 · 인덱스 충돌 $reservationConflicts개 · 고아 인덱스 $orphanReservations개 · 쓰기 실패 $failedWrites개 · 검증 불일치 $verificationMismatches개';
}

class UserCodeReservationBackfillService {
  UserCodeReservationBackfillService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _roots =>
      _firestore.collection('user_accounts');

  CollectionReference<Map<String, dynamic>> get _reservations =>
      _firestore.collection('user_account_codes');

  String _codeOf(Map<String, dynamic> data) {
    for (final field in <String>['codeNumber', 'phone', 'handle']) {
      final value = AccountCodeNumber.normalize((data[field] ?? '').toString());
      if (AccountCodeNumber.isValid(value)) return value;
    }
    return '';
  }

  Set<String> _loginIdentifiersOf(Map<String, dynamic> data) {
    final out = <String>{};
    for (final field in <String>['codeNumber', 'phone', 'handle']) {
      final value = AccountCodeNumber.normalize((data[field] ?? '').toString());
      if (AccountCodeNumber.isValid(value)) out.add(value);
    }
    return out;
  }

  String _areaOf(Map<String, dynamic> data) {
    final current = (data['currentArea'] ?? '').toString().trim();
    if (current.isNotEmpty) return current;
    final selected = (data['selectedArea'] ?? '').toString().trim();
    if (selected.isNotEmpty) return selected;
    final areas = data['areas'];
    if (areas is List && areas.isNotEmpty) {
      final first = areas.first.toString().trim();
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  Future<UserCodeReservationBackfillResult> run({
    UserCodeReservationBackfillLogger? onLog,
  }) async {
    onLog?.call('user_accounts 코드번호 수집을 시작합니다.', 0.03);
    final rootSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _roots.get(
      const GetOptions(source: Source.server),
    ), source: 'user_code_reservation_backfill_service.get');
    final codeOwners = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final identifierOwners = <String, Set<String>>{};
    var invalidRootCodes = 0;

    for (final doc in rootSnapshot.docs) {
      final data = doc.data();
      final code = _codeOf(data);
      if (!AccountCodeNumber.isValid(code)) {
        invalidRootCodes += 1;
      } else {
        codeOwners.putIfAbsent(code, () => []).add(doc);
      }
      for (final identifier in _loginIdentifiersOf(data)) {
        identifierOwners.putIfAbsent(identifier, () => <String>{}).add(doc.id);
      }
    }

    final conflictedIdentifiers = identifierOwners.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();
    final duplicateCodes = conflictedIdentifiers.length;
    onLog?.call(
      'Root 스캔 완료: ${rootSnapshot.docs.length}개, 유효하지 않은 코드 $invalidRootCodes개, 중복 코드 $duplicateCodes개',
      0.18,
    );

    final reservationSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _reservations.get(
      const GetOptions(source: Source.server),
    ), source: 'user_code_reservation_backfill_service.get');
    final reservationByCode = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final doc in reservationSnapshot.docs) doc.id: doc,
    };
    final rootIds = rootSnapshot.docs.map((doc) => doc.id).toSet();
    final rootCodeById = <String, String>{
      for (final doc in rootSnapshot.docs) doc.id: _codeOf(doc.data()),
    };
    var orphanReservations = 0;
    final reservationConflictIds = <String>{};
    for (final reservation in reservationSnapshot.docs) {
      final owner = (reservation.data()['userId'] ?? '').toString().trim();
      if (owner.isEmpty || !rootIds.contains(owner)) {
        orphanReservations += 1;
        continue;
      }
      if (rootCodeById[owner] != reservation.id) {
        reservationConflictIds.add(reservation.id);
      }
    }

    final pending = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    var alreadyMatchedReservations = 0;

    for (final entry in codeOwners.entries) {
      if (entry.value.length != 1) continue;
      final code = entry.key;
      if (conflictedIdentifiers.contains(code)) continue;
      final root = entry.value.single;
      final reservation = reservationByCode[code];
      if (reservation == null) {
        pending[code] = root;
        continue;
      }
      final owner = (reservation.data()['userId'] ?? '').toString().trim();
      if (owner == root.id) {
        alreadyMatchedReservations += 1;
      } else {
        reservationConflictIds.add(code);
      }
    }
    final reservationConflicts = reservationConflictIds.length;

    onLog?.call(
      '인덱스 검사 완료: 신규 ${pending.length}개, 일치 $alreadyMatchedReservations개, 충돌 $reservationConflicts개, 고아 $orphanReservations개',
      0.32,
    );

    var createdReservations = 0;
    var failedWrites = 0;
    final entries = pending.entries.toList(growable: false);
    for (var index = 0; index < entries.length; index += 1) {
      final entry = entries[index];
      final code = entry.key;
      final root = entry.value;
      try {
        final created = await _firestore.runTransaction<bool>((tx) async {
          final rootSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(root.reference), source: 'user_code_reservation_backfill_service.get');
          final reservationRef = _reservations.doc(code);
          final reservationSnap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => tx.get(reservationRef), source: 'user_code_reservation_backfill_service.get');
          if (!rootSnap.exists || rootSnap.data() == null) {
            throw StateError('ROOT_MISSING:${root.id}');
          }
          final currentCode = _codeOf(rootSnap.data()!);
          if (currentCode != code) {
            throw StateError('ROOT_CODE_CHANGED:${root.id}');
          }
          if (reservationSnap.exists) {
            final owner = (reservationSnap.data()?['userId'] ?? '').toString().trim();
            if (owner != root.id) {
              throw StateError('RESERVATION_CONFLICT:$code');
            }
            return false;
          }
          FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => tx.set(
            reservationRef,
            <String, dynamic>{
              'userId': root.id,
              'codeNumber': code,
              'area': _areaOf(rootSnap.data()!),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          ));
          return true;
        });
        if (created) {
          createdReservations += 1;
        } else {
          alreadyMatchedReservations += 1;
        }
      } on FirebaseException catch (error) {
        failedWrites += 1;
        debugPrint(
          'user_account_codes backfill 실패 code=${error.code} codeNumber=${AccountCodeNumber.mask(code)}',
        );
      } catch (error) {
        failedWrites += 1;
        debugPrint(
          'user_account_codes backfill 실패 error=${error.runtimeType} codeNumber=${AccountCodeNumber.mask(code)}',
        );
      }
      final progress = entries.isEmpty ? 0.72 : 0.34 + ((index + 1) / entries.length) * 0.38;
      onLog?.call(
        '코드 인덱스 반영: ${index + 1}/${entries.length}',
        progress,
      );
    }

    onLog?.call('코드 인덱스와 Root 연결을 재검증합니다.', 0.78);
    final verifyReservations = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _reservations.get(
      const GetOptions(source: Source.server),
    ), source: 'user_code_reservation_backfill_service.get');
    final verifyByCode = <String, Map<String, dynamic>>{
      for (final doc in verifyReservations.docs) doc.id: doc.data(),
    };
    var verificationMismatches = 0;
    for (final entry in codeOwners.entries) {
      if (entry.value.length != 1 || conflictedIdentifiers.contains(entry.key)) {
        continue;
      }
      final owner = entry.value.single.id;
      final reservationOwner = (verifyByCode[entry.key]?['userId'] ?? '').toString().trim();
      if (reservationOwner != owner) {
        verificationMismatches += 1;
      }
    }

    final result = UserCodeReservationBackfillResult(
      rootTotal: rootSnapshot.docs.length,
      reservationTotal: verifyReservations.docs.length,
      createdReservations: createdReservations,
      alreadyMatchedReservations: alreadyMatchedReservations,
      invalidRootCodes: invalidRootCodes,
      duplicateCodes: duplicateCodes,
      reservationConflicts: reservationConflicts,
      orphanReservations: orphanReservations,
      failedWrites: failedWrites,
      verificationMismatches: verificationMismatches,
    );
    onLog?.call('코드 인덱스 동기화 결과: ${result.summary}', 1);
    return result;
  }
}
