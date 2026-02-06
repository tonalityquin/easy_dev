import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
import 'plate_repository.dart';
import 'plate_stream_service.dart';
import 'plate_write_service.dart';
import 'plate_query_service.dart';
import 'plate_creation_service.dart';
import 'plate_status_service.dart';

class FirestorePlateRepository implements PlateRepository {
  final PlateStreamService _streamService = PlateStreamService();
  final PlateWriteService _writeService = PlateWriteService();
  final PlateQueryService _queryService = PlateQueryService();
  final PlateCreationService _creationService = PlateCreationService();
  final PlateStatusService _statusService = PlateStatusService();

  @override
  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
        bool countInitialSnapshot = false,
      }) {
    return _streamService.streamToCurrentArea(
      type,
      area,
      descending: descending,
      location: location,
      countInitialSnapshot: countInitialSnapshot, // ✅ (3)
    );
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots(
      String area, {
        bool descending = true,
        bool countInitialSnapshot = false, // ✅ (3)
      }) {
    return _streamService.departureUnpaidSnapshots(
      area: area,
      descending: descending,
      countInitialSnapshot: countInitialSnapshot, // ✅
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

  /// ✅ 수정: deletePlate가 (area/syncViews)를 받아 plates + view 정리까지 가능하도록 위임
  ///
  /// - 기존 호출( deletePlate(documentId) )도 그대로 동작 (named optional)
  /// - area가 넘어오면 더 정확하게 view 정리 가능
  /// - syncViews=false로 비용 최소화(plates만 삭제) 선택 가능
  @override
  Future<void> deletePlate(
      String documentId, {
        String? area,
        bool syncViews = true,
      }) {
    return _writeService.deletePlate(
      documentId,
      area: area,
      syncViews: syncViews,
    );
  }

  @override
  Future<void> recordWhoPlateClick(
      String id,
      bool isSelected, {
        String? selectedBy,
        required String area,
      }) {
    return _writeService.recordWhoPlateClick(
      id,
      isSelected,
      selectedBy: selectedBy,
      area: area,
    ); // ✅ (2)
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
  Future<List<PlateModel>> fourDigitForTabletQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitForTabletQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitDepartureCompletedQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
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
  Future<void> setMonthlyMemoAndStatusOnly({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    bool skipIfDocMissing = true,
  }) {
    return _statusService.setMonthlyMemoAndStatusOnly(
      plateNumber: plateNumber,
      area: area,
      createdBy: createdBy,
      customStatus: customStatus,
      statusList: statusList,
      skipIfDocMissing: skipIfDocMissing,
    );
  }

  @override
  Future<void> deletePlateStatus(String plateNumber, String area) {
    return _statusService.deletePlateStatus(plateNumber, area);
  }

  /// ✅ 수정: updatedAt을 여기서 Timestamp.now()로 넣지 않음
  /// - PlateWriteService.updatePlate가 트랜잭션 내부에서 updatedAt을 FieldValue.serverTimestamp()로 강제 세팅하므로,
  ///   여기서 클라이언트 시간을 넣는 것은 의미가 없고 오해 여지가 있어 제거
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
    final updateData = <String, dynamic>{
      'type': toType.firestoreValue,
      'location': location,
      'userName': userName,
      if (resetSelection) ...{
        'isSelected': false,
        'selectedBy': null,
      },
      if (includeEndTime) 'endTime': DateTime.now(),
      if (isLockedFee == true) 'isLockedFee': true,
      if (lockedAtTimeInSeconds != null)
        'lockedAtTimeInSeconds': lockedAtTimeInSeconds,
      if (lockedFeeAmount != null) 'lockedFeeAmount': lockedFeeAmount,
      if (log != null) 'logs': FieldValue.arrayUnion([log.toMap()]),
    };

    await updatePlate(documentId, updateData);
  }
}
