import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';

abstract class PlateRepository {
  // ========= Streams =========
  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
      });

  /// 출차 완료(미정산) 원본 스냅샷 스트림 (docChanges 사용용)
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots(
      String area, {
        bool descending,
      });

  // ========= Counts =========
  Future<int> getPlateCountForTypePage(PlateType type, String area);
  Future<int> getPlateCountToCurrentArea(String area);
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

  // ========= Queries =========
  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  });
  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  });
  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
    required String plateFourDigit,
    required String area,
  });
  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  });
  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  });
  Future<PlateModel?> getPlate(String documentId);

  // ========= Writes =========
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate);
  Future<void> updatePlate(
      String documentId,
      Map<String, dynamic> updatedFields, {
        PlateLogModel? log,
      });
  Future<void> deletePlate(String documentId);

  Future<void> recordWhoPlateClick(
      String id,
      bool isSelected, {
        String? selectedBy,
      });

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
    bool isLockedFee = false,           // ✅ 구현과 일치
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
  });

  // ========= Plate Status =========
  Future<Map<String, dynamic>?> getPlateStatus(String plateNumber, String area);

  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
  });

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

  // ========= Transitions =========
  /// 상태 전이 공통 메서드 (구현체에서 Firestore 업데이트)
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
  });

  /// 출차 완료 전용 업데이트(헬퍼)
  Future<void> updateToDepartureCompleted(String documentId, PlateModel plate);
}
