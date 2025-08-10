import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../../repositories/plate/plate_repository.dart';
import 'input_log_plate.dart';
import '../../models/plate_log_model.dart';

class InputPlate with ChangeNotifier {
  final PlateRepository _plateRepository;
  final InputLogPlate _logState;

  InputPlate(this._plateRepository, this._logState);

  Future<bool> isPlateNumberDuplicated(String plateNumber, String area) async {
    return await _plateRepository.checkDuplicatePlate(
      plateNumber: plateNumber,
      area: area,
    );
  }

  Future<bool> registerPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required AreaState areaState,
    required UserState userState,

    // ✅ 추가: 변동/고정/정기 타입
    required String selectedBillType,

    String? billingType,
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
    String? customStatus,
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
      await _plateRepository.addPlate(
        plateNumber: plateNumber,
        location: correctedLocation,
        area: areaState.currentArea,
        userName: userState.name,
        plateType: plateType,
        billingType: billingType,
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
        customStatus: customStatus,

        // ✅ 추가: 레포로 전달
        selectedBillType: selectedBillType,
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
      final errorMessage = error.toString().contains('이미 등록된 번호판')
          ? '이미 등록된 번호판입니다: $plateNumber'
          : '오류 발생: $error';
      showFailedSnackbar(context, errorMessage);
      return false;
    }
  }
}
