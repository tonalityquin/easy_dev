import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../models/plate_log_model.dart';
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

      final updatedFields = <String, dynamic>{};

      if (plate.location != location) {
        updatedFields['location'] = {
          'from': plate.location,
          'to': location,
        };
      }

      if (plate.billingType != billingType) {
        updatedFields['billingType'] = {
          'from': plate.billingType,
          'to': billingType,
        };
      }

      if (plate.plateNumber != newPlateNumber) {
        updatedFields['plateNumber'] = {
          'from': plate.plateNumber,
          'to': newPlateNumber,
        };
      }

      if (updatedFields.isNotEmpty) {
        debugPrint('🗂 변경 내역: $updatedFields');

        final log = PlateLogModel(
          plateNumber: newPlateNumber,
          division: areaState.currentDivision,
          area: plate.area,
          from: collectionKey,
          to: collectionKey,
          action: 'modify',
          performedBy: userState.name,
          timestamp: DateTime.now(),
          updatedFields: updatedFields,
        );

        await _plateRepository.updatePlate(
          documentId,
          {
            // 실제 변경된 필드만 업데이트
            if (plate.location != location) 'location': location,
            if (plate.billingType != billingType) 'billingType': billingType,
            if (plate.plateNumber != newPlateNumber) 'plate_number': newPlateNumber,
            'updatedAt': Timestamp.now(),
          },
          log: log,
        );
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
