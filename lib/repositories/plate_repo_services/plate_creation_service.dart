import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart'; // ✅

class PlateCreationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addPlate({
    required String plateNumber,
    required String location,
    required String area,
    required PlateType plateType,
    required String userName,
    String? billingType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    required String region,
    List<String>? imageUrls,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
    required String selectedBillType,
  }) async {
    final documentId = '${plateNumber}_$area';

    int? regularAmount;
    int? regularDurationHours;

    if (selectedBillType != '정기' && billingType != null && billingType.isNotEmpty) {
      try {
        final billDoc =
        await _firestore.collection('bill').doc('${billingType}_$area').get();

        // ✅ bill read 1회
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: 1,
          source: 'PlateCreationService.addPlate.billRead',
        );

        if (billDoc.exists) {
          final billData = billDoc.data()!;

          basicStandard = billData['basicStandard'] ?? 0;
          basicAmount = billData['basicAmount'] ?? 0;
          addStandard = billData['addStandard'] ?? 0;
          addAmount = billData['addAmount'] ?? 0;

          regularAmount = billData['regularAmount'];
          regularDurationHours = billData['regularDurationHours'];
        } else {
          throw Exception('Firestore에서 정산 데이터를 찾을 수 없음');
        }
      } catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'bill.read.forPlateCreation',
            'collection': 'bill',
            'docId': '${billingType}_$area',
            'inputs': {
              'billingType': billingType,
              'area': area,
              'selectedBillType': selectedBillType,
            },
            'error': {
              'type': e.runtimeType.toString(),
              if (e is FirebaseException) 'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['bill', 'read', 'error'],
          }, level: 'error');
        } catch (_) {}
        debugPrint("🔥 정산 정보 로드 실패: $e");
        throw Exception("Firestore 정산 정보 로드 실패: $e");
      }
    } else if (selectedBillType == '정기') {
      basicStandard = 0;
      basicAmount = 0;
      addStandard = 0;
      addAmount = 0;
    }

    final plateFourDigit =
    plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;

    final effectiveIsLockedFee =
        isLockedFee || (billingType == null || billingType.trim().isEmpty);

    final plate = PlateModel(
      id: documentId,
      plateNumber: plateNumber,
      plateFourDigit: plateFourDigit,
      type: plateType.firestoreValue,
      requestTime: DateTime.now(),
      endTime: endTime,
      location: location.isNotEmpty ? location : '미지정',
      area: area,
      userName: userName,
      billingType: billingType,
      statusList: statusList ?? [],
      basicStandard: basicStandard ?? 0,
      basicAmount: basicAmount ?? 0,
      addStandard: addStandard ?? 0,
      addAmount: addAmount ?? 0,
      region: region,
      imageUrls: imageUrls,
      isSelected: false,
      selectedBy: null,
      isLockedFee: effectiveIsLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
      paymentMethod: paymentMethod,
      customStatus: customStatus,
      regularAmount: regularAmount,
      regularDurationHours: regularDurationHours,
    );

    final plateWithLog = plate.addLog(
      action: '생성',
      performedBy: userName,
      from: '',
      to: location.isNotEmpty ? location : '미지정',
    );

    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      int writes = 0;
      int reads = 0;

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        reads += 1; // ✅ tx.get → read 1

        if (snap.exists) {
          final data = snap.data();
          final existingTypeStr = (data?['type'] as String?) ?? '';
          final existingType = PlateType.values.firstWhere(
                (t) => t.firestoreValue == existingTypeStr,
            orElse: () => PlateType.parkingRequests,
          );

          if (!_isAllowedDuplicate(existingType)) {
            debugPrint("🚨 중복된 번호판 등록 시도: $plateNumber (${existingType.name})");
            throw Exception("이미 등록된 번호판입니다: $plateNumber");
          } else {
            // 기존 logs 보존 + 신규 로그 append
            final List<Map<String, dynamic>> existingLogs = (() {
              final raw = data?['logs'];
              if (raw is List) {
                return raw
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
              }
              return <Map<String, dynamic>>[];
            })();

            final List<Map<String, dynamic>> newLogs =
            (plateWithLog.logs ?? []).map((e) => e.toMap()).toList();

            final List<Map<String, dynamic>> mergedLogs = [...existingLogs, ...newLogs];

            final partial = <String, dynamic>{
              PlateFields.type: plateType.firestoreValue,
              PlateFields.updatedAt: Timestamp.now(),
              if (location.isNotEmpty) PlateFields.location: location,
              if (endTime != null) PlateFields.endTime: endTime,
              if (billingType != null && billingType.trim().isNotEmpty)
                PlateFields.billingType: billingType,
              if (imageUrls != null) PlateFields.imageUrls: imageUrls,
              if (paymentMethod != null) PlateFields.paymentMethod: paymentMethod,
              if (lockedAtTimeInSeconds != null)
                PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
              if (lockedFeeAmount != null) PlateFields.lockedFeeAmount: lockedFeeAmount,
              PlateFields.isLockedFee: effectiveIsLockedFee,
              PlateFields.logs: mergedLogs,
            };

            final bool wasLocked = (data?['isLockedFee'] == true);
            if (wasLocked) {
              final countersRef =
              _firestore.collection('plate_counters').doc('area_$area');
              tx.set(
                countersRef,
                {'departureCompletedEvents': FieldValue.increment(1)},
                SetOptions(merge: true),
              );
              writes += 1; // counters set
            }

            tx.update(docRef, partial);
            writes += 1; // plates update
          }
        } else {
          tx.set(docRef, plateWithLog.toMap());
          writes += 1; // plates set
        }
      });

      // ✅ 트랜잭션에서 발생한 read/write 집계 보고
      if (reads > 0) {
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: reads,
          source: 'PlateCreationService.addPlate.tx',
        );
      }
      if (writes > 0) {
        await UsageReporter.instance.report(
          area: area,
          action: 'write',
          n: writes,
          source: 'PlateCreationService.addPlate.tx',
        );
      }
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plate.create.transaction',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'location': location,
            'plateType': plateType.firestoreValue,
            'selectedBillType': selectedBillType,
            'billingType': billingType,
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plate', 'create', 'transaction', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }

    // ✅ plate_status upsert → write 1
    if (customStatus != null && customStatus.trim().isNotEmpty) {
      final statusDocRef = _firestore.collection('plate_status').doc(documentId);
      final now = Timestamp.now();
      final expireAt =
      Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));

      final payload = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'updatedAt': now,
        'createdBy': userName,
        'expireAt': expireAt,
        'area': area,
      };

      try {
        await statusDocRef.set(payload, SetOptions(merge: true));
        await UsageReporter.instance.report(
          area: area,
          action: 'write',
          n: 1,
          source: 'PlateCreationService.addPlate.statusUpsert',
        );
      } on FirebaseException catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'plateStatus.upsert.set',
            'collection': 'plate_status',
            'docPath': statusDocRef.path,
            'docId': documentId,
            'error': {
              'type': e.runtimeType.toString(),
              'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['plateStatus', 'upsert', 'set', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      } catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'plateStatus.upsert.unknown',
            'collection': 'plate_status',
            'docPath': statusDocRef.path,
            'docId': documentId,
            'error': {
              'type': e.runtimeType.toString(),
              if (e is FirebaseException) 'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['plateStatus', 'upsert', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    }
  }

  bool _isAllowedDuplicate(PlateType type) {
    return type == PlateType.departureCompleted;
  }
}
