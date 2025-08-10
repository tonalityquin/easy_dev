import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';

abstract class PlateRepository {
  Stream<List<PlateModel>> streamToCurrentArea(
    PlateType type,
    String area, {
    bool descending = true,
    String? location,
  });

  Future<int> getPlateCountForTypePage(
    PlateType type,
    String area,
  );

  Future<int> getPlateCountToCurrentArea(String area);

  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  });

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate);

  Future<void> updatePlate(
    String documentId,
    Map<String, dynamic> updatedFields, {
    PlateLogModel? log,
  });

  Future<void> deletePlate(String documentId);

  Future<PlateModel?> getPlate(String documentId);

  Future<void> recordWhoPlateClick(String id, bool isSelected, {String? selectedBy});

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
    required String selectedBillType,
    List<String>? imageUrls,
    bool isLockedFee,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
  });

  Future<int> getPlateCountForClockInPage(
    PlateType type, {
    DateTime? selectedDate,
    required String area,
  });

  Future<int> getPlateCountForClockOutPage(
    PlateType type, {
    DateTime? selectedDate,
    required String area,
  });

  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  });

  // 🔹 plate_status 관련 메서드
  Future<Map<String, dynamic>?> getPlateStatus(String plateNumber, String area);

  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
  });

  /// ✅ 정기 plate_status 저장 (수정됨)
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
  });

  Future<void> deletePlateStatus(String plateNumber, String area);

  // 🔹 상태 전이용 공통 메서드
  Future<void> transitionPlateState({
    required String documentId,
    required PlateType toType,
    required String location,
    required String userName,
    bool resetSelection = true,
    bool includeEndTime = false,
    bool? isLockedFee,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    PlateLogModel? log,
  }) async {
    final docRef = FirebaseFirestore.instance.collection('plates').doc(documentId);
    final updateData = <String, dynamic>{
      'type': toType.name,
      'location': location,
      'userName': userName,
      'updatedAt': Timestamp.now(),
      if (includeEndTime) 'endTime': Timestamp.now(),
      if (isLockedFee != null) 'isLockedFee': isLockedFee,
      if (lockedAtTimeInSeconds != null) 'lockedAtTimeInSeconds': lockedAtTimeInSeconds,
      if (lockedFeeAmount != null) 'lockedFeeAmount': lockedFeeAmount,
      if (resetSelection) ...{
        'isSelected': false,
        'selectedBy': null,
      },
      if (log != null) 'logs': FieldValue.arrayUnion([log.toMap()]),
    };

    await docRef.update(updateData);
  }

  // 🔹 출차 완료 전용 업데이트
  Future<void> updateToDepartureCompleted(String documentId, PlateModel plate);
}
