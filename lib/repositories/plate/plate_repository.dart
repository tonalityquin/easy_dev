import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

abstract class PlateRepository {
  Stream<List<PlateModel>> getPlatesByTypeAndArea(
    PlateType type,
    String area, {
    int? limit,
  });

  Future<int> getPlateCountByTypeAndArea(
    PlateType type,
    String area,
  );

  Future<List<PlateModel>> getPlatesByFourDigit({
    required String plateFourDigit,
    required String area,
  });

  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  });

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate); // v

  Future<void> updatePlate(String documentId, Map<String, dynamic> updatedFields); // v

  Future<void> deletePlate(String documentId);

  Future<PlateModel?> getPlate(String documentId);

  Future<void> updatePlateSelection(String id, bool isSelected, {String? selectedBy});

  Future<void> addRequestOrCompleted({
    // v
    required String plateNumber,
    required String location,
    required String area,
    required PlateType plateType,
    required String userName,
    String? adjustmentType,
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
  });

  Future<List<String>> getAvailableLocations(String area);

  Future<int> getPlateCountByType(PlateType type, {DateTime? selectedDate});

  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  });
}
