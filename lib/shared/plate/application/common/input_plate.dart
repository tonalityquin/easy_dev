import 'package:flutter/material.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/repositories/plate_repository.dart';

class InputPlate with ChangeNotifier {
  final PlateRepository _plateRepository;

  InputPlate(this._plateRepository);

  Future<bool> commonRegisterPlateEntry({
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
    String? manufacturerName,
    String? modelName,
    String? priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
  }) async {
    final correctedLocation = location.isEmpty ? '미지정' : location;
    final plateType = isLocationSelected ? PlateType.parkingCompleted : PlateType.parkingRequests;

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
        manufacturerName: manufacturerName,
        modelName: modelName,
        priority1SlotKey: priority1SlotKey,
        priority2SlotKey: priority2SlotKey,
        priority3SlotKey: priority3SlotKey,
      );

      
      notifyListeners();
      return true;
    } catch (error) {
      if (!context.mounted) return false;
      if (error.toString().contains('이미 등록된 번호판')) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.duplicateActiveEntry,
        );
      } else {
        showFailedSnackbar(context, '오류 발생: $error');
      }
      return false;
    }
  }
}
