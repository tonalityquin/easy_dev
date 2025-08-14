import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
import 'plate_repository.dart';
import 'plate_stream_service.dart';
import 'plate_write_service.dart';
import 'plate_query_service.dart';
import 'plate_count_service.dart';
import 'plate_creation_service.dart';
import 'plate_status_service.dart'; // ✅ 추가된 import

class FirestorePlateRepository implements PlateRepository {
  final PlateStreamService _streamService = PlateStreamService();
  final PlateWriteService _writeService = PlateWriteService();
  final PlateQueryService _queryService = PlateQueryService();
  final PlateCountService _countService = PlateCountService();
  final PlateCreationService _creationService = PlateCreationService();
  final PlateStatusService _statusService = PlateStatusService(); // ✅ 서비스 인스턴스 추가

  @override
  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
      }) {
    return _streamService.streamToCurrentArea(
      type,
      area,
      descending: descending,
      location: location,
    );
  }

  /// ✅ 추가: 출차 완료(미정산) 전용 원본 스냅샷 스트림
  /// - isLockedFee == false 문서만
  /// - QuerySnapshot을 그대로 노출(PlateState에서 docChanges 사용 용도)
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots(
      String area, {
        bool descending = true,
      }) {
    return _streamService.departureUnpaidSnapshots(
      area: area,
      descending: descending,
    );
  }

  @override
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) {
    return _writeService.addOrUpdatePlate(documentId, plate);
  }

  @override
  Future<void> updatePlate(
      String documentId,
      Map<String, dynamic> updatedFields, {
        PlateLogModel? log,
      }) {
    return _writeService.updatePlate(documentId, updatedFields, log: log);
  }

  @override
  Future<void> deletePlate(String documentId) {
    return _writeService.deletePlate(documentId);
  }

  @override
  Future<void> recordWhoPlateClick(String id, bool isSelected, {String? selectedBy}) {
    return _writeService.recordWhoPlateClick(id, isSelected, selectedBy: selectedBy);
  }

  @override
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
  }) {
    // ✅ 내부적으로 PlateLogModel 로그가 삽입된 PlateModel이 생성되어 저장됨
    return _creationService.addPlate(
      plateNumber: plateNumber,
      location: location,
      area: area,
      plateType: plateType,
      userName: userName,
      billingType: billingType,
      statusList: statusList,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
      region: region,
      imageUrls: imageUrls,
      isLockedFee: isLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
      endTime: endTime,
      paymentMethod: paymentMethod,
      customStatus: customStatus,
      selectedBillType: selectedBillType,
    );
  }

  @override
  Future<PlateModel?> getPlate(String documentId) {
    return _queryService.getPlate(documentId);
  }

  @override
  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  }) {
    return _queryService.getPlatesByLocation(
      type: type,
      area: area,
      location: location,
    );
  }

  @override
  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitCommonQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitSignatureQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  }) {
    return _queryService.checkDuplicatePlate(
      plateNumber: plateNumber,
      area: area,
    );
  }

  @override
  Future<int> getPlateCountForTypePage(
      PlateType type,
      String area,
      ) {
    return _countService.getPlateCountForTypePage(type, area);
  }

  @override
  Future<int> getPlateCountToCurrentArea(String area) {
    return _countService.getPlateCountToCurrentArea(area);
  }

  @override
  Future<int> getPlateCountForClockInPage(
      PlateType type, {
        DateTime? selectedDate,
        required String area,
      }) {
    return _countService.getPlateCountForClockInPage(
      type,
      selectedDate: selectedDate,
      area: area,
    );
  }

  @override
  Future<int> getPlateCountForClockOutPage(
      PlateType type, {
        DateTime? selectedDate,
        required String area,
      }) {
    return _countService.getPlateCountForClockOutPage(
      type,
      selectedDate: selectedDate,
      area: area,
    );
  }

  // 🔸 plate_status 관련 메서드 위임
  @override
  Future<Map<String, dynamic>?> getPlateStatus(String plateNumber, String area) {
    return _statusService.getPlateStatus(plateNumber, area);
  }

  @override
  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
  }) {
    return _statusService.setPlateStatus(
      plateNumber: plateNumber,
      area: area,
      customStatus: customStatus,
      statusList: statusList,
      createdBy: createdBy,
    );
  }

  @override
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
  }) {
    return _statusService.setMonthlyPlateStatus(
      plateNumber: plateNumber,
      area: area,
      createdBy: createdBy,
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
  }

  @override
  Future<void> deletePlateStatus(String plateNumber, String area) {
    return _statusService.deletePlateStatus(plateNumber, area);
  }

  // ✅ 상태 전이
  @override
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
    final updateData = {
      'type': toType.firestoreValue,
      'location': location,
      'userName': userName,
      'updatedAt': Timestamp.now(),
      if (resetSelection) ...{
        'isSelected': false,
        'selectedBy': null,
      },
      if (includeEndTime) 'endTime': DateTime.now(),
      if (isLockedFee == true) 'isLockedFee': true,
      if (lockedAtTimeInSeconds != null) 'lockedAtTimeInSeconds': lockedAtTimeInSeconds,
      if (lockedFeeAmount != null) 'lockedFeeAmount': lockedFeeAmount,
      if (log != null) 'logs': FieldValue.arrayUnion([log.toMap()]),
    };

    await updatePlate(documentId, updateData);
  }

  @override
  Future<void> updateToDepartureCompleted(String documentId, PlateModel plate) async {
    await transitionPlateState(
      documentId: documentId,
      toType: PlateType.departureCompleted,
      location: plate.location,
      userName: plate.userName,
      includeEndTime: true,
      isLockedFee: plate.isLockedFee,
      lockedAtTimeInSeconds: plate.lockedAtTimeInSeconds,
      lockedFeeAmount: plate.lockedFeeAmount,
    );
  }
}
