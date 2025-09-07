import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/type_package/debugs/firestore_logger.dart';

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
    await FirestoreLogger().log('addPlate called: $documentId, plateNumber=$plateNumber');

    // (기존) 정산 정보 로딩/세팅 로직 그대로 유지
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

          await FirestoreLogger().log('addPlate billing data loaded: $billingType');
        } else {
          throw Exception('Firestore에서 정산 데이터를 찾을 수 없음');
        }
      } catch (e) {
        debugPrint("🔥 정산 정보 로드 실패: $e");
        await FirestoreLogger().log('addPlate billing error: $e');
        throw Exception("Firestore 정산 정보 로드 실패: $e");
      }
    } else if (selectedBillType == '정기') {
      basicStandard = 0;
      basicAmount = 0;
      addStandard = 0;
      addAmount = 0;
    }

    final plateFourDigit = plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;

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
          await FirestoreLogger().log('addPlate error: duplicate plate - $plateNumber');
          throw Exception("이미 등록된 번호판입니다: $plateNumber");
        } else {
          debugPrint("⚠️ ${existingType.name} 상태 중복 등록 허용(트랜잭션): $plateNumber");
          await FirestoreLogger().log('addPlate allowed duplicate (tx): $plateNumber (${existingType.name})');
          // 허용 시 업데이트(merge)
          tx.set(docRef, plateWithLog.toMap(), SetOptions(merge: true));
        }
      } else {
        // 신규 생성
        tx.set(docRef, plateWithLog.toMap());
      }
    });

    // (기존) 커스텀 상태 업서트 로직 그대로 유지
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
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') {
          await statusDocRef.set(payload, SetOptions(merge: true));
        } else {
          rethrow;
        }
      }

      await FirestoreLogger().log('addPlate customStatus upserted (safe merge): $documentId');
    }

    await FirestoreLogger().log('addPlate success: $documentId');
  }

  bool _isAllowedDuplicate(PlateType type) {
    return type == PlateType.departureCompleted;
  }
}
