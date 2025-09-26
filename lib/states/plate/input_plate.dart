import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../../repositories/plate_repo_services/plate_repository.dart';

class InputPlate with ChangeNotifier {
  final PlateRepository _plateRepository;

  InputPlate(this._plateRepository);

  Future<bool> registerPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required AreaState areaState,
    required UserState userState,
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
    final plateType =
    isLocationSelected ? PlateType.parkingCompleted : PlateType.parkingRequests;

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
        selectedBillType: selectedBillType,
      );

      // ✅ 별도 로그 저장 호출 제거
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
