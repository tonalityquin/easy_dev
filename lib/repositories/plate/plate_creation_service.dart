import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';
import 'plate_write_service.dart';
import 'plate_query_service.dart';

class PlateCreationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PlateWriteService _writeService = PlateWriteService();
  final PlateQueryService _queryService = PlateQueryService();

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

    // ✅ 추가: 변동/고정/정기 타입 전달(필수)
    required String selectedBillType,
  }) async {
    final documentId = '${plateNumber}_$area';
    await FirestoreLogger().log('addPlate called: $documentId, plateNumber=$plateNumber');

    // 중복 검사
    final existingPlate = await _queryService.getPlate(documentId);
    if (existingPlate != null) {
      final existingType = PlateType.values.firstWhere(
        (type) => type.firestoreValue == existingPlate.type,
        orElse: () => PlateType.parkingRequests,
      );

      if (!_isAllowedDuplicate(existingType)) {
        debugPrint("🚨 중복된 번호판 등록 시도: $plateNumber (${existingType.name})");
        await FirestoreLogger().log('addPlate error: duplicate plate - $plateNumber');
        throw Exception("이미 등록된 번호판입니다: $plateNumber");
      } else {
        debugPrint("⚠️ ${existingType.name} 상태 중복 등록 허용: $plateNumber");
        await FirestoreLogger().log('addPlate allowed duplicate: $plateNumber (${existingType.name})');
      }
    }

    int? regularAmount;
    int? regularDurationHours;

    // ✅ 핵심 분기: '정기'가 아니고 billingType이 있을 때만 bill 조회
    if (selectedBillType != '정기' && billingType != null && billingType.isNotEmpty) {
      try {
        final billDoc = await _firestore.collection('bill').doc('${billingType}_$area').get();
        if (billDoc.exists) {
          final billData = billDoc.data()!;

          // 변동/고정 정산 세팅
          basicStandard = billData['basicStandard'] ?? 0;
          basicAmount = billData['basicAmount'] ?? 0;
          addStandard = billData['addStandard'] ?? 0;
          addAmount = billData['addAmount'] ?? 0;

          // (고정에서 쓸 수도 있는) 정기 관련 필드가 정의되어 있으면 유지
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
      // ✅ 정기: 사전 결제 → 0분/0원 강제
      basicStandard = 0;
      basicAmount = 0;
      addStandard = 0;
      addAmount = 0;

      // 정기 메타는 plate_status에 저장/관리. plate에는 필요시 라벨만 저장할 수 있음.
    }

    final plateFourDigit = plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;

    // billingType이 비었으면 요금 잠금 처리
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
      action: 'create',
      performedBy: userName,
      from: '',
      to: location.isNotEmpty ? location : '미지정',
    );

    debugPrint("🔥 저장할 plate: ${plateWithLog.toMap()}");
    await _writeService.addOrUpdatePlate(documentId, plateWithLog);

    if (customStatus != null && customStatus.trim().isNotEmpty) {
      final statusDocRef = _firestore.collection('plate_status').doc(documentId);
      final now = Timestamp.now();
      final expireAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));

      final payload = <String, dynamic>{
        // ✅ 보호 필드(type, countType, regular*, periodUnit, startDate, endDate, payment_history) 건드리지 않음
        'customStatus': customStatus.trim(),
        'updatedAt': now,
        'createdBy': userName,
        'expireAt': expireAt,
        // 필요하면 area도 처음 생성시에만 남기고 싶다면 merge 시 포함 가능
        'area': area,
      };

      try {
        // 먼저 필요한 필드만 부분 업데이트 (기존 문서가 있으면 안전)
        await statusDocRef.update(payload);
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') {
          // 문서가 없으면 merge:true로 생성 (다른 필드는 그대로)
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
