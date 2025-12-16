// lib/repositories/plate_repo_services/plate_status_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';
// import '../../utils/usage_reporter.dart';

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docRef(String plateNumber, String area) =>
      _firestore.collection('plate_status').doc('${plateNumber}_$area');

  // ✅ 월정기 전용 컬렉션 참조
  DocumentReference<Map<String, dynamic>> _monthlyDocRef(String plateNumber, String area) =>
      _firestore.collection('monthly_plate_status').doc('${plateNumber}_$area');

  bool _isEmptyInput(String customStatus, List<String> statusList) =>
      customStatus.trim().isEmpty && statusList.isEmpty;

  /// ✅ 월정기 저장용 "빈 입력" 판정
  /// - 월정기는 customStatus/statusList가 비어있어도 문서를 저장해야 하므로,
  ///   monthly 필드까지 모두 비어있는 경우에만 deleteWhenEmpty를 적용한다.
  bool _isEmptyMonthlyPayload({
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationHours,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
  }) {
    final memoEmpty = customStatus.trim().isEmpty;
    final statusesEmpty = statusList.isEmpty;

    final countTypeEmpty = countType.trim().isEmpty;
    final amountEmpty = regularAmount == 0;
    final durationEmpty = regularDurationHours == 0;

    final regularTypeEmpty = regularType.trim().isEmpty;
    final startEmpty = startDate.trim().isEmpty;
    final endEmpty = endDate.trim().isEmpty;
    final periodUnitEmpty = periodUnit.trim().isEmpty;

    final specialNoteEmpty = (specialNote ?? '').trim().isEmpty;
    final extendedEmpty = isExtended == null;

    return memoEmpty &&
        statusesEmpty &&
        countTypeEmpty &&
        amountEmpty &&
        durationEmpty &&
        regularTypeEmpty &&
        startEmpty &&
        endEmpty &&
        periodUnitEmpty &&
        specialNoteEmpty &&
        extendedEmpty;
  }

  /// plate_status 세팅
  /// 빈 입력 → blind delete (READ 0 / DELETE 1)
  /// 값 있음 → tx.get 1 + set(merge) 1 (READ 1 / WRITE 1)
  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
    bool deleteWhenEmpty = true,
    Map<String, dynamic>? extra,
  }) async {
    final ref = _docRef(plateNumber, area);
    try {
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          await ref.delete().timeout(const Duration(seconds: 10));
          /*await UsageReporter.instance.report(area: area, action: 'delete', n: 1, source: 'PlateStatusService.setPlateStatus.delete');*/
        }
        return;
      }

      final data = <String, dynamic>{
        ...?extra,
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'area': area,
      };

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) data['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));

      /*await UsageReporter.instance.report(area: area, action: 'read', n: 1, source: 'PlateStatusService.setPlateStatus.tx');
      await UsageReporter.instance.report(area: area, action: 'write', n: 1, source: 'PlateStatusService.setPlateStatus.tx');*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.set',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'customStatusLen': customStatus.length,
            'statusListLen': statusList.length,
            'deleteWhenEmpty': deleteWhenEmpty,
            if (extra != null) 'extraKeys': extra.keys.take(30).toList(),
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.set.timeout',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area, 'deleteWhenEmpty': deleteWhenEmpty},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.set.unknown',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// ✅ 월정기 상태 세팅
  /// - 월정기는 customStatus/statusList가 비어도 저장 가능해야 함
  /// - truly empty payload(월정기 필드까지 전부 empty)일 때만 deleteWhenEmpty 적용
  Future<void> setMonthlyPlateStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationHours,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
    bool deleteWhenEmpty = true,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);
    try {
      final emptyMonthly = _isEmptyMonthlyPayload(
        customStatus: customStatus,
        statusList: statusList,
        countType: countType,
        regularAmount: regularAmount,
        regularDurationHours: regularDurationHours,
        regularType: regularType,
        startDate: startDate,
        endDate: endDate,
        periodUnit: periodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      if (emptyMonthly) {
        if (deleteWhenEmpty) {
          await ref.delete().timeout(const Duration(seconds: 10));
        }
        return;
      }

      final base = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'type': '정기',
        'countType': countType,
        'regularAmount': regularAmount,
        'regularDurationHours': regularDurationHours,
        'regularType': regularType,
        'startDate': startDate,
        'endDate': endDate,
        'periodUnit': periodUnit,
        'area': area,
        if (specialNote != null) 'specialNote': specialNote,
        if (isExtended != null) 'isExtended': isExtended,
      };

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) base['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, base, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthly',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'countType': countType,
            'regularAmount': regularAmount,
            'regularDurationHours': regularDurationHours,
            'regularType': regularType,
            'periodUnit': periodUnit,
            'hasSpecialNote': specialNote != null,
            'isExtended': isExtended,
            'deleteWhenEmpty': deleteWhenEmpty,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthly.timeout',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthly.unknown',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// ✅ 정기(월정기)일 때: monthly_plate_status에 "메모/상태"만 업데이트
  /// - 핵심: update()를 사용하여 "문서가 없으면 생성되지 않도록" 강제
  /// - skipIfDocMissing=true 이고 not-found면 조용히 return
  Future<void> setMonthlyMemoAndStatusOnly({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    bool skipIfDocMissing = true,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);

    final data = <String, dynamic>{
      'customStatus': customStatus.trim(),
      'statusList': statusList,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'area': area,
    };

    try {
      await ref.update(data).timeout(const Duration(seconds: 10));
    } on FirebaseException catch (e, st) {
      // 문서 미존재: 정책상 생성하지 않음
      if (skipIfDocMissing && e.code == 'not-found') {
        return;
      }

      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthlyMemoAndStatusOnly',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'customStatusLen': customStatus.length,
            'statusListLen': statusList.length,
            'skipIfDocMissing': skipIfDocMissing,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthlyMemo', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthlyMemoAndStatusOnly.timeout',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area, 'skipIfDocMissing': skipIfDocMissing},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthlyMemo', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthlyMemoAndStatusOnly.unknown',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area, 'skipIfDocMissing': skipIfDocMissing},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthlyMemo', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> deletePlateStatus(String plateNumber, String area) async {
    final ref = _docRef(plateNumber, area);
    try {
      await ref.delete();
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.delete',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.delete.timeout',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.delete.unknown',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
