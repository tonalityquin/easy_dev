import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../../repositories/plate/plate_repository.dart';
import 'log_plate.dart';
import '../../models/plate_log_model.dart';

class InputPlate with ChangeNotifier {
  final PlateRepository _plateRepository;
  final LogPlateState _logState;

  InputPlate(this._plateRepository, this._logState);

  Future<bool> isPlateNumberDuplicated(String plateNumber, String area) async {
    return await _plateRepository.checkDuplicatePlate(
      plateNumber: plateNumber,
      area: area,
    );
  }

  Future<bool> handlePlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required AreaState areaState,
    required UserState userState,
    String? adjustmentType,
    List<String>? statusList,
    int basicStandard = 0,
    int basicAmount = 0,
    int addStandard = 0,
    int addAmount = 0,
    required String region,
    List<String>? imageUrls,
    int? lockedFee,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    String? customStatus, // ✅ 추가됨
  }) async {
    final correctedLocation = location.isEmpty ? '미지정' : location;
    final plateType = isLocationSelected ? PlateType.parkingCompleted : PlateType.parkingRequests;

    if (plateType != PlateType.departureCompleted &&
        await isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      if (!context.mounted) return false;
      showFailedSnackbar(context, '이미 등록된 번호판입니다: $plateNumber');
      return false;
    }

    try {
      await _plateRepository.addRequestOrCompleted(
        plateNumber: plateNumber,
        location: correctedLocation,
        area: areaState.currentArea,
        userName: userState.name,
        plateType: plateType,
        adjustmentType: adjustmentType,
        statusList: statusList ?? [],
        basicStandard: basicStandard,
        basicAmount: basicAmount,
        addStandard: addStandard,
        addAmount: addAmount,
        region: region,
        imageUrls: imageUrls,
        isLockedFee: isLockedFee,
        lockedAtTimeInSeconds: lockedAtTimeInSeconds,
        lockedFeeAmount: lockedFeeAmount,
        customStatus: customStatus, // ✅ 저장 요청에 포함
      );

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: areaState.currentArea,
          division: areaState.currentDivision,
          from: '-',
          to: plateType.label,
          action: plateType.label,
          performedBy: userState.name,
          timestamp: DateTime.now(),
        ),
        division: areaState.currentDivision,
        area: areaState.currentArea,
      );

      notifyListeners();
      return true;
    } catch (error) {
      if (!context.mounted) return false;

      final errorMessage = error.toString().contains('이미 등록된 번호판') ? '이미 등록된 번호판입니다: $plateNumber' : '오류 발생: $error';

      showFailedSnackbar(context, errorMessage);
      return false;
    }
  }

  Future<bool> updatePlateInfo({
    required BuildContext context,
    required PlateModel plate,
    required String newPlateNumber,
    required String location,
    required AreaState areaState,
    required UserState userState,
    String? adjustmentType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    String? region,
    List<String>? imageUrls,
    bool? isLockedFee,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    String? customStatus, // ✅ 추가됨
  }) async {
    try {
      final oldDocumentId = '${plate.plateNumber}_${plate.area}';
      final newDocumentId = '${newPlateNumber}_${plate.area}';

      final updatedPlate = plate.copyWith(
        plateNumber: newPlateNumber,
        location: location,
        userName: userState.name,
        adjustmentType: adjustmentType,
        statusList: statusList,
        basicStandard: basicStandard,
        basicAmount: basicAmount,
        addStandard: addStandard,
        addAmount: addAmount,
        region: region,
        imageUrls: imageUrls,
        isLockedFee: isLockedFee ?? plate.isLockedFee,
        lockedAtTimeInSeconds: lockedAtTimeInSeconds ?? plate.lockedAtTimeInSeconds,
        lockedFeeAmount: lockedFeeAmount ?? plate.lockedFeeAmount,
        updatedAt: DateTime.now(),
        customStatus: customStatus ?? plate.customStatus, // ✅ 반영
      );

      if (oldDocumentId != newDocumentId) {
        await _plateRepository.deletePlate(oldDocumentId);
      }

      await _plateRepository.addOrUpdatePlate(newDocumentId, updatedPlate);

      if (!context.mounted) return false;
      showSuccessSnackbar(context, '정보 수정 완료');
      notifyListeners();

      return true;
    } catch (e) {
      if (!context.mounted) return false;
      showFailedSnackbar(context, '정보 수정 실패: $e');
      return false;
    }
  }
}
