import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';

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

    // (기존) 정산 정보 로딩/세팅 로직 유지 + 실패 로깅
    int? regularAmount;
    int? regularDurationHours;

    if (selectedBillType != '정기' && billingType != null && billingType.isNotEmpty) {
      try {
        final billDoc = await _firestore.collection('bill').doc('${billingType}_$area').get();
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
        // Firestore 로딩 실패 로깅만
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

    // 도메인 의도: billingType 비어 있으면 잠금요금으로 간주
    final effectiveIsLockedFee = isLockedFee || (billingType == null || billingType.trim().isEmpty);

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

    // 🔒 트랜잭션으로 중복 불가 보장 (레이스 컨디션 방지)
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);

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
            debugPrint("⚠️ ${existingType.name} 상태 중복 등록 허용(트랜잭션): $plateNumber");
            tx.set(docRef, plateWithLog.toMap(), SetOptions(merge: true));
          }
        } else {
          // 신규 생성
          tx.set(docRef, plateWithLog.toMap());
        }
      });
    } catch (e, st) {
      // Firestore 트랜잭션 실패 로깅만 (도메인 예외 포함하되 code가 있으면 함께 기록)
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

    // (기존) 커스텀 상태 업서트 로직 유지 + 실패 로깅
    if (customStatus != null && customStatus.trim().isNotEmpty) {
      final statusDocRef = _firestore.collection('plate_status').doc(documentId);
      final now = Timestamp.now();
      final expireAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));

      final payload = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'updatedAt': now,
        'createdBy': userName,
        'expireAt': expireAt,
        'area': area,
      };

      try {
        await statusDocRef.update(payload);
      } on FirebaseException catch (e, st) {
        if (e.code == 'not-found') {
          // 없으면 생성 시도
          try {
            await statusDocRef.set(payload, SetOptions(merge: true));
          } catch (e2, st2) {
            try {
              await DebugFirestoreLogger().log({
                'op': 'plateStatus.upsert.set',
                'collection': 'plate_status',
                'docPath': statusDocRef.path,
                'docId': documentId,
                'error': {
                  'type': e2.runtimeType.toString(),
                  if (e2 is FirebaseException) 'code': e2.code,
                  'message': e2.toString(),
                },
                'stack': st2.toString(),
                'tags': ['plateStatus', 'upsert', 'set', 'error'],
              }, level: 'error');
            } catch (_) {}
            rethrow;
          }
        } else {
          // update 실패 로깅
          try {
            await DebugFirestoreLogger().log({
              'op': 'plateStatus.upsert.update',
              'collection': 'plate_status',
              'docPath': statusDocRef.path,
              'docId': documentId,
              'error': {
                'type': e.runtimeType.toString(),
                'code': e.code,
                'message': e.toString(),
              },
              'stack': st.toString(),
              'tags': ['plateStatus', 'upsert', 'update', 'error'],
            }, level: 'error');
          } catch (_) {}
          rethrow;
        }
      } catch (e, st) {
        // FirebaseException 이외 예외도 로깅(네트워크/플랫폼 등)
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
