import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'plate_repository.dart';
import 'plate_stream_service.dart';
import 'plate_write_service.dart';
import 'plate_query_service.dart';
import 'plate_count_service.dart';
import 'plate_creation_service.dart';

class FirestorePlateRepository implements PlateRepository {
  final PlateStreamService _streamService = PlateStreamService();
  final PlateWriteService _writeService = PlateWriteService();
  final PlateQueryService _queryService = PlateQueryService();
  final PlateCountService _countService = PlateCountService();
  final PlateCreationService _creationService = PlateCreationService();

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

  @override
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) {
    return _writeService.addOrUpdatePlate(documentId, plate);
  }

  @override
  Future<void> updatePlate(String documentId, Map<String, dynamic> updatedFields) {
    return _writeService.updatePlate(documentId, updatedFields);
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
}
