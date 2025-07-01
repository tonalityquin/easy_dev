import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../plate/plate_state.dart'; // ✅ PlateState import
import '../../repositories/plate/plate_repository.dart';
import 'dart:developer' as dev;

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
    required String collectionKey, // ❌ 사용되지 않음 (유지하되 무시)
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
      final oldDocumentId = '${plate.plateNumber}_${plate.area}';
      final newDocumentId = '${newPlateNumber}_${plate.area}';

      dev.log("📝 updatePlateInfo() 호출됨");
      dev.log("📌 documentId: $oldDocumentId → $newDocumentId");
      dev.log("📌 newPlateNumber: $newPlateNumber");
      dev.log("📌 imageUrls: $imageUrls");

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

      if (oldDocumentId != newDocumentId) {
        await _plateRepository.deletePlate(oldDocumentId);
      }

      await _plateRepository.addOrUpdatePlate(newDocumentId, updatedPlate);

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

        dev.log('🗂 변경 내역: ${changes.join(', ')}');
      }

      if (!context.mounted) return false;
      final plateState = context.read<PlateState>();
      await plateState.subscribePlateData();

      notifyListeners();
      return true;
    } catch (e) {
      dev.log('❌ 정보 수정 실패: $e');
      if (!context.mounted) return false;
      showFailedSnackbar(context, '정보 수정 실패: $e');
      return false;
    }
  }
}
