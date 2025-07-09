import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

abstract class PlateRepository {
  Stream<List<PlateModel>> streamToCurrentArea(
    PlateType type,
    String area, {
    bool descending = true,
  });

  Future<int> getPlateCountForTypePage(
    PlateType type,
    String area,
  );

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

  Future<void> updatePlate(String documentId, Map<String, dynamic> updatedFields);

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
    int basicStandard,
    int basicAmount,
    int addStandard,
    int addAmount,
    required String region,
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
}
