import '../../application/common/view_doc_rows_store.dart';
import '../enums/plate_type.dart';
import '../models/plate_log_model.dart';
import '../models/plate_model.dart';
import '../models/plate_out_log_search_result.dart';
import '../services/plate_status_record.dart';

class PlateLogReadException implements Exception {
  final String message;
  final Object? cause;

  const PlateLogReadException(this.message, {this.cause});

  @override
  String toString() => message;
}

class PlateFetchResult {
  final List<PlateModel> items;
  final String sourceLabel;

  const PlateFetchResult({
    required this.items,
    required this.sourceLabel,
  });
}

abstract class PlateRepository {
  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateOutLogSearchResult>> searchPlateOutLogsByFourDigit({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateModel>> fourDigitForTabletQuery({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
    required String plateFourDigit,
    required String area,
  });

  Future<PlateModel?> getPlate(String documentId);

  Future<List<PlateModel>> fetchSelectedPlatesByUser({
    required String userName,
    required List<PlateType> plateTypes,
  });

  Future<PlateFetchResult> fetchPlatesByTypeAndArea({
    required PlateType type,
    required String area,
    required bool descending,
    bool cacheFirst = true,
  });

  Future<void> upsertViewItem({
    required String collection,
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    required String primaryAtField,
  });

  Future<void> removeViewItem({
    required String collection,
    required String area,
    required String plateDocId,
  });

  Future<void> transitionPlateType({
    required String plateId,
    required String actor,
    required PlateType fromType,
    required PlateType toType,
    required String area,
    required String location,
    required String eventAtField,
    bool forceOverride = true,
  });

  Stream<List<ViewRowData>> watchViewRows({
    required String collection,
    required String area,
    required String primaryAtField,
  });

  Future<List<PlateLogModel>> fetchPlateLogs({
    String? plateId,
    String? plateNumber,
    required String area,
    bool descending = false,
  });

  Future<void> appendPlateLog({
    required String plateId,
    required Map<String, dynamic> log,
  });

  Future<void> settlePlateBilling({
    required String documentId,
    required int lockedAtTimeInSeconds,
    required int lockedFeeAmount,
    required String paymentMethod,
    required PlateLogModel log,
  });

  Future<void> cancelPlateBilling({
    required String documentId,
    required PlateLogModel log,
  });

  Future<PlateStatusRecord?> fetchLatestPlateStatus({
    required String plateNumber,
    required String area,
  });

  Future<PlateStatusRecord?> fetchMonthlyPlateStatus({
    required String plateNumber,
    required String area,
  });

  Future<void> upsertMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    String? countType,
  });

  Future<void> clearMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
  });

  Future<List<String>> fetchViewLocations({
    required String collectionName,
    required String area,
  });

  Stream<List<PlateStatusRecord>> watchMonthlyPlateStatuses({
    required String area,
  });

  Future<void> deleteMonthlyPlateStatus({
    required String documentId,
  });

  Future<void> recordMonthlyPayment({
    required String plateNumber,
    required String area,
    required String paidBy,
    required int amount,
    required String note,
    required bool extended,
  });

  Future<void> extendMonthlyDateRange({
    required String plateNumber,
    required String area,
    required String startDate,
    required String endDate,
    required String extendedBy,
  });

  Future<void> clearMonthlyMemoAndStatusWithAudit({
    required String plateNumber,
    required String area,
    required String clearedBy,
  });

  Future<bool> hasMonthlyParkingByArea({
    required String area,
  });

  Future<Map<String, dynamic>?> fetchViewDocumentData({
    required String collection,
    required String area,
  });

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate);

  Future<void> updatePlate(
    String documentId,
    Map<String, dynamic> updatedFields, {
    PlateLogModel? log,
  });

  Future<void> deletePlate(
    String documentId, {
    String? area,
    bool syncViews = true,
  });

  Future<void> recordWhoPlateClick(
    String id,
    bool isSelected, {
    String? selectedBy,
    required String area,
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
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
    String? manufacturerName,
    String? modelName,
    String? priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
  });

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

  Future<void> setMonthlyMemoAndStatusOnly({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    bool skipIfDocMissing = true,
  });

  Future<void> deletePlateStatus(String plateNumber, String area);

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

  Future<int> countPlatesByAreaAndType({
    required String area,
    required PlateType plateType,
  });
}
