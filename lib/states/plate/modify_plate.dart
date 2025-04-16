import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../enums/plate_type.dart';
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

  Future<bool> isPlateNumberDuplicated(String plateNumber, String area) async {
    final typesToCheck = [
      PlateType.parkingRequests,
      PlateType.parkingCompleted,
      PlateType.departureRequests,
    ];

    for (final type in typesToCheck) {
      final plates = await _plateRepository.getPlatesByArea(type, area);
      if (plates.any((plate) => plate.plateNumber == plateNumber)) {
        dev.log("🚨 중복된 번호판 발견: $plateNumber (type: ${type.firestoreValue})");
        return true;
      }
    }

    return false;
  }

  Future<void> handlePlateEntry({
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
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
  }) async {
    if (await isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      if (!context.mounted) return;
      showFailedSnackbar(context, '이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    final correctedLocation = location.isEmpty ? '미지정' : location;
    final plateType = isLocationSelected ? PlateType.parkingCompleted : PlateType.parkingRequests;

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
        isLockedFee: isLockedFee,
        lockedAtTimeInSeconds: lockedAtTimeInSeconds,
        lockedFeeAmount: lockedFeeAmount,
      );

      if (!context.mounted) return;
      showSuccessSnackbar(context, '${plateType.label} 완료');
    } catch (error) {
      if (!context.mounted) return;
      showFailedSnackbar(context, '오류 발생: $error');
    }
  }

  Future<bool> updatePlateInfo({
    required BuildContext context,
    required PlateModel plate,
    required String newPlateNumber,
    required String location,
    required AreaState areaState,
    required UserState userState,
    required String collectionKey, // ❌ 사용되지 않음 (유지하되 무시)
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
      );

      if (oldDocumentId != newDocumentId) {
        await _plateRepository.deletePlate(oldDocumentId);
      }

      await _plateRepository.addOrUpdatePlate(newDocumentId, updatedPlate);

      final isLocationChanged = plate.location != location;
      final isAdjustmentChanged = plate.adjustmentType != adjustmentType;

      if (isLocationChanged || isAdjustmentChanged) {
        final changes = <String>[];

        if (isLocationChanged) {
          changes.add('위치: ${plate.location} → $location');
        }

        if (isAdjustmentChanged) {
          final fromAdj = plate.adjustmentType ?? '-';
          final toAdj = adjustmentType ?? '-';
          changes.add('정산: $fromAdj → $toAdj');
        }

        dev.log('🗂 변경 내역: ${changes.join(', ')}');
      }

      if (!context.mounted) return false;
      final plateState = context.read<PlateState>();
      await plateState.fetchPlateData();

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
