import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../../repositories/plate/plate_repository.dart';

class ModifyPlate with ChangeNotifier {
  final PlateRepository _plateRepository;

  ModifyPlate(this._plateRepository);

  Future<bool> modifyPlateInfo({
    required BuildContext context,
    required PlateModel plate,
    required String newPlateNumber,
    required String location,
    required AreaState areaState,
    required UserState userState,
    required String collectionKey,
    String? billingType,
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
  }) async {
    try {
      final documentId = '${plate.plateNumber}_${plate.area}';

      debugPrint("📝 updatePlateInfo() 호출됨");
      debugPrint("📌 documentId: $documentId");
      debugPrint("📌 newPlateNumber: $newPlateNumber");
      debugPrint("📌 imageUrls: $imageUrls");

      final updatedPlate = plate.copyWith(
        plateNumber: newPlateNumber,
        location: location,
        userName: userState.name,
        billingType: billingType,
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
      );

      await _plateRepository.addOrUpdatePlate(documentId, updatedPlate);

      final isLocationChanged = plate.location != location;
      final isBillChanged = plate.billingType != billingType;

      if (isLocationChanged || isBillChanged) {
        final changes = <String>[];

        if (isLocationChanged) {
          changes.add('위치: ${plate.location} → $location');
        }
        if (isBillChanged) {
          final fromBill = plate.billingType ?? '-';
          final toBill = billingType ?? '-';
          changes.add('정산: $fromBill → $toBill');
        }

        debugPrint('🗂 변경 내역: ${changes.join(', ')}');
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ 정보 수정 실패: $e');
      if (!context.mounted) return false;
      showFailedSnackbar(context, '정보 수정 실패: $e');
      return false;
    }
  }
}
