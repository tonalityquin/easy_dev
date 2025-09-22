import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart'; // ✅

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docRef(String plateNumber, String area) =>
      _firestore.collection('plate_status').doc('${plateNumber}_$area');

  bool _isEmptyInput(String customStatus, List<String> statusList) =>
      customStatus.trim().isEmpty && statusList.isEmpty;

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
          final snap = await ref.get().timeout(const Duration(seconds: 10));
          if (snap.exists) {
            await ref.delete().timeout(const Duration(seconds: 10));
            // ✅ delete 1회
            await UsageReporter.instance.report(
              area: area,
              action: 'delete',
              n: 1,
              source: 'PlateStatusService.setPlateStatus.delete',
            );
          }
          // get 1회 읽음
          await UsageReporter.instance.report(
            area: area,
            action: 'read',
            n: 1,
            source: 'PlateStatusService.setPlateStatus.prefetch',
          );
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
        if (!snap.exists) {
          data['createdAt'] = FieldValue.serverTimestamp();
        }
        tx.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));

      // ✅ 트랜잭션: read 1 + write 1
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateStatusService.setPlateStatus.tx',
      );
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'PlateStatusService.setPlateStatus.tx',
      );
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.set',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'customStatusLen': customStatus.length,
            'statusListLen': statusList.length,
            'deleteWhenEmpty': false,
            if (extra != null) 'extraKeys': extra.keys.take(30).toList(),
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.set.timeout',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'deleteWhenEmpty': false,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.set.unknown',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

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
    final ref = _docRef(plateNumber, area);

    try {
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          final snap = await ref.get().timeout(const Duration(seconds: 10));
          if (snap.exists) {
            await ref.delete().timeout(const Duration(seconds: 10));
            await UsageReporter.instance.report(
              area: area,
              action: 'delete',
              n: 1,
              source: 'PlateStatusService.setMonthlyPlateStatus.delete',
            );
          }
          await UsageReporter.instance.report(
            area: area,
            action: 'read',
            n: 1,
            source: 'PlateStatusService.setMonthlyPlateStatus.prefetch',
          );
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
        if (!snap.exists) {
          base['createdAt'] = FieldValue.serverTimestamp();
        }
        tx.set(ref, base, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));

      // ✅ read + write
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateStatusService.setMonthlyPlateStatus.tx',
      );
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'PlateStatusService.setMonthlyPlateStatus.tx',
      );
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.setMonthly',
          'collection': 'plate_status',
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
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.setMonthly.timeout',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.setMonthly.unknown',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> deletePlateStatus(String plateNumber, String area) async {
    final ref = _docRef(plateNumber, area);
    try {
      await ref.delete();

      // ✅ delete 1회
      await UsageReporter.instance.report(
        area: area,
        action: 'delete',
        n: 1,
        source: 'PlateStatusService.deletePlateStatus',
      );
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.delete',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.delete.timeout',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plateStatus.delete.unknown',
          'collection': 'plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
