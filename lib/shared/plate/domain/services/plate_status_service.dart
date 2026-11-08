import '../../../../app/diagnostics/firebase_activity_meter.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'plate_status_record.dart';

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _plateStatusRoot = 'plate_status';
  static const String _monthsSub = 'months';
  static const String _platesSub = 'plates';

  String _monthKey(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}';

  String _safeArea(String area) => area.isNotEmpty ? area : 'unknown';

  String _plateDocId(String plateNumber, String area) => '${plateNumber}_$area';

  String _normalizedPlateKey(String plateNumber) =>
      plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();

  String _plateFourDigit(String plateNumber) {
    final key = _normalizedPlateKey(plateNumber);
    if (key.length <= 4) return key;
    return key.substring(key.length - 4);
  }

  DateTime _nextMonthStartUtc(DateTime dt) =>
      DateTime.utc(dt.year, dt.month + 1, 1);

  DocumentReference<Map<String, dynamic>> _docRef(
    String plateNumber,
    String area, {
    DateTime? forDate,
  }) {
    final dt = forDate ?? DateTime.now();
    final month = _monthKey(dt);
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    return _firestore
        .collection(_plateStatusRoot)
        .doc(safeArea)
        .collection(_monthsSub)
        .doc(month)
        .collection(_platesSub)
        .doc(docId);
  }

  DocumentReference<Map<String, dynamic>> _monthlyDocRef(
    String plateNumber,
    String area,
  ) =>
      _firestore.collection('monthly_plate_status').doc('${plateNumber}_$area');

  bool _isEmptyMonthlyPayload({
    required String customStatus,
    required String countType,
    required int regularAmount,
    required int regularDurationValue,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
  }) {
    return customStatus.trim().isEmpty &&
        countType.trim().isEmpty &&
        regularAmount == 0 &&
        regularDurationValue == 0 &&
        regularType.trim().isEmpty &&
        startDate.trim().isEmpty &&
        endDate.trim().isEmpty &&
        periodUnit.trim().isEmpty &&
        (specialNote ?? '').trim().isEmpty &&
        isExtended == null;
  }

  List<DateTime> _candidateMonths(DateTime base, {int lookbackMonths = 1}) {
    final out = <DateTime>[];
    for (var index = 0; index <= lookbackMonths; index++) {
      out.add(DateTime(base.year, base.month - index, 1));
    }
    return out;
  }

  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required String createdBy,
    bool deleteWhenEmpty = true,
    Map<String, dynamic>? extra,
    DateTime? forDate,
    int deleteLookbackMonths = 1,
  }) async {
    final dt = forDate ?? DateTime.now();
    final safeArea = _safeArea(area);
    final ref = _docRef(plateNumber, safeArea, forDate: dt);

    try {
      if (customStatus.trim().isEmpty) {
        if (deleteWhenEmpty) {
          final months =
              _candidateMonths(dt, lookbackMonths: deleteLookbackMonths);
          for (final month in months) {
            final candidate = _docRef(plateNumber, safeArea, forDate: month);
            await candidate.delete().trackFirestore('DELETE', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status').timeout(const Duration(seconds: 10));
          }
        }
        return;
      }

      final data = <String, dynamic>{
        ...?extra,
        'plateNumber': plateNumber,
        'plateDocId': _plateDocId(plateNumber, safeArea),
        'plateKey': _normalizedPlateKey(plateNumber),
        'plate_four_digit': _plateFourDigit(plateNumber),
        'statusScope': _plateStatusRoot,
        'monthKey': _monthKey(dt),
        'customStatus': customStatus.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'area': safeArea,
        'expireAt': Timestamp.fromDate(_nextMonthStartUtc(dt)),
      };

      await _firestore.runTrackedActivityTransaction((transaction) async {
        final snapshot =
            await transaction.get(ref).trackFirestore('GET', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status', readPurpose: 'STATUS_HISTORY_MONTH_UPSERT_VALIDATION').timeout(const Duration(seconds: 10));
        if (!snapshot.exists) {
          data['createdAt'] = FieldValue.serverTimestamp();
        }
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'shared/plate/domain/services/plate_status_service.dart', result: 'staged');
        transaction.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> setMonthlyPlateStatus({
    required String plateNumber,
    required String area,
    required String region,
    required String createdBy,
    required String customStatus,
    required String countType,
    required int regularAmount,
    required int regularDurationValue,
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
        countType: countType,
        regularAmount: regularAmount,
        regularDurationValue: regularDurationValue,
        regularType: regularType,
        startDate: startDate,
        endDate: endDate,
        periodUnit: periodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      if (emptyMonthly) {
        if (deleteWhenEmpty) {
          await ref.delete().trackFirestore('DELETE', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status').timeout(const Duration(seconds: 10));
        }
        return;
      }

      final data = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'type': '정기',
        'countType': countType,
        'regularAmount': regularAmount,
        'regularDurationValue': regularDurationValue,
        'regularDurationHours': regularDurationValue,
        'regularType': regularType,
        'startDate': startDate,
        'endDate': endDate,
        'periodUnit': periodUnit,
        'area': area,
        'region': region.trim().isEmpty ? '전국' : region.trim(),
        if (specialNote != null) 'specialNote': specialNote,
        if (isExtended != null) 'isExtended': isExtended,
      };

      await _firestore.runTrackedActivityTransaction((transaction) async {
        final snapshot =
            await transaction.get(ref).trackFirestore('GET', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status', readPurpose: 'MONTHLY_STATUS_UPSERT_VALIDATION').timeout(const Duration(seconds: 10));
        if (!snapshot.exists) {
          data['createdAt'] = FieldValue.serverTimestamp();
        }
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'shared/plate/domain/services/plate_status_service.dart', result: 'staged');
        transaction.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> setMonthlyMemoAndStatusOnly({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    bool skipIfDocMissing = true,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);
    final data = <String, dynamic>{
      'customStatus': customStatus.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'area': area,
    };

    try {
      await _firestore.runTrackedActivityTransaction((transaction) async {
        final snapshot = await transaction.get(ref).trackFirestore('GET', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status', readPurpose: 'MONTHLY_MEMO_UPDATE_STATE_VALIDATION');
        final source = snapshot.data();
        if (!snapshot.exists || source == null) {
          if (skipIfDocMissing) return;
          throw const MonthlyPlateStatusWriteException(
            '정기 상태 문서를 찾지 못했습니다.',
          );
        }
        final record = PlateStatusRecord.fromMap(
          source,
          docId: snapshot.id,
        );
        if (!record.isActiveAt(DateTime.now())) {
          throw const MonthlyPlateStatusWriteException(
            '정기 주차 기간이 만료되어 상태 메모를 반영하지 않았습니다.',
          );
        }
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_UPDATE', source: 'shared/plate/domain/services/plate_status_service.dart', result: 'staged');
        transaction.update(ref, data);
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException catch (error) {
      if (skipIfDocMissing && error.code == 'not-found') return;
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> upsertMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    String? countType,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);
    final data = <String, dynamic>{
      'customStatus': customStatus.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMemoUpdatedBy': createdBy,
      if ((countType ?? '').trim().isNotEmpty) 'countType': countType!.trim(),
    };

    try {
      await _firestore.runTrackedActivityTransaction((transaction) async {
        final snapshot =
            await transaction.get(ref).trackFirestore('GET', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status', readPurpose: 'MONTHLY_MEMO_UPSERT_STATE_VALIDATION').timeout(const Duration(seconds: 10));
        if (!snapshot.exists) return;
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'shared/plate/domain/services/plate_status_service.dart', result: 'staged');
        transaction.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> clearMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);

    try {
      await ref.update(
        <String, dynamic>{
          'customStatus': '',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ).trackFirestore('UPDATE', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status').timeout(const Duration(seconds: 10));
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') return;
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deletePlateStatus(
    String plateNumber,
    String area, {
    DateTime? forDate,
    int lookbackMonths = 1,
  }) async {
    final dt = forDate ?? DateTime.now();
    final safeArea = _safeArea(area);

    try {
      final months = _candidateMonths(dt, lookbackMonths: lookbackMonths);
      for (final month in months) {
        final candidate = _docRef(plateNumber, safeArea, forDate: month);
        await candidate.delete().trackFirestore('DELETE', 'shared/plate/domain/services/plate_status_service.dart', collection: 'monthly_plate_status');
      }
    } on FirebaseException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }
}
