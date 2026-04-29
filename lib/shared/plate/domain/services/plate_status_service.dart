import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

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
          String plateNumber, String area) =>
      _firestore.collection('monthly_plate_status').doc('${plateNumber}_$area');

  bool _isEmptyInput(String customStatus, List<String> statusList) =>
      customStatus.trim().isEmpty && statusList.isEmpty;

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

  List<DateTime> _candidateMonths(DateTime base, {int lookbackMonths = 1}) {
    final out = <DateTime>[];
    for (int i = 0; i <= lookbackMonths; i++) {
      out.add(DateTime(base.year, base.month - i, 1));
    }
    return out;
  }

  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
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
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          final months =
              _candidateMonths(dt, lookbackMonths: deleteLookbackMonths);
          for (final m in months) {
            final r = _docRef(plateNumber, safeArea, forDate: m);
            await r.delete().timeout(const Duration(seconds: 10));
          }
        }
        return;
      }

      final plateDocId = _plateDocId(plateNumber, safeArea);
      final normalizedKey = _normalizedPlateKey(plateNumber);
      final fourDigit = _plateFourDigit(plateNumber);
      final monthKey = _monthKey(dt);

      final data = <String, dynamic>{
        ...?extra,
        'plateNumber': plateNumber,
        'plateDocId': plateDocId,
        'plateKey': normalizedKey,
        'plate_four_digit': fourDigit,
        'statusScope': _plateStatusRoot,
        'monthKey': monthKey,
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'area': safeArea,
        'expireAt': Timestamp.fromDate(_nextMonthStartUtc(dt)),
      };

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) data['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, data, SetOptions(merge: true));
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
    } on FirebaseException catch (e) {
      if (skipIfDocMissing && e.code == 'not-found') {
        return;
      }

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
    required List<String> statusList,
    String? countType,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);

    final data = <String, dynamic>{
      'customStatus': customStatus.trim(),
      'statusList': statusList,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'area': area,
      'type': '정기',
      if ((countType ?? '').trim().isNotEmpty) 'countType': countType!.trim(),
    };

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) data['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, data, SetOptions(merge: true));
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
      await ref.set(
        <String, dynamic>{
          'customStatus': '',
          'statusList': <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 10));
    } on FirebaseException {
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
      for (final m in months) {
        final r = _docRef(plateNumber, safeArea, forDate: m);
        await r.delete();
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
