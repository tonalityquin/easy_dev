import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../models/plate_log_model.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../plate/plate_state.dart'; // ✅ PlateState import
import 'log_plate.dart';
import '../../repositories/plate/plate_repository.dart';
import 'dart:developer' as dev;

class ModifyPlate with ChangeNotifier {
  final PlateRepository _plateRepository;
  final LogPlateState _logState;

  ModifyPlate(this._plateRepository, this._logState);

  Future<bool> isPlateNumberDuplicated(String plateNumber, String area) async {
    final collectionsToCheck = [
      'parking_requests',
      'parking_completed',
      'departure_requests',
    ];

    for (var collection in collectionsToCheck) {
      final plates = await _plateRepository.getPlatesByArea(collection, area);
      if (plates.any((plate) => plate.plateNumber == plateNumber)) {
        dev.log("🚨 중복된 번호판 발견: $plateNumber (컬렉션: $collection)");
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
    bool isLockedFee = false, // ✅ 추가
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount, // ✅ 추가
// ✅ 추가
  }) async {
    if (await isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      if (!context.mounted) return;
      showFailedSnackbar(context, '이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    final correctedLocation = location.isEmpty ? '미지정' : location;
    final collection = isLocationSelected ? 'parking_completed' : 'parking_requests';
    final type = isLocationSelected ? '입차 완료' : '입차 요청';

    try {
      await _plateRepository.addRequestOrCompleted(
        collection: collection,
        plateNumber: plateNumber,
        location: correctedLocation,
        area: areaState.currentArea,
        userName: userState.name,
        type: type,
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

      await _logState.saveLog(
        PlateLogModel(
          plateNumber: plateNumber,
          area: areaState.currentArea,
          from: '-',
          to: collection,
          action: type,
          performedBy: userState.name,
          timestamp: DateTime.now(),
        ),
      );

      if (!context.mounted) return;
      showSuccessSnackbar(context, '$type 완료');
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
    required String collectionKey,
    String? adjustmentType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    String? region,
    List<String>? imageUrls,
    bool? isLockedFee, // ✅ 추가
    int? lockedAtTimeInSeconds, // ✅ 추가
    int? lockedFeeAmount,
  }) async {
    try {
      final documentId = '${plate.plateNumber}_${plate.area}';

      // 🔍 디버깅 로그
      dev.log("📝 updatePlateInfo() 호출됨");
      dev.log("📌 documentId: $documentId");
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

      await _plateRepository.addOrUpdateDocument(
        collectionKey,
        documentId,
        updatedPlate.toMap(),
      );

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

      // ✅ PlateState 최신화 → 요금 재계산 반영
      if (!context.mounted) return false; // 함수 반환값에 맞게 처리
      final plateState = context.read<PlateState>();
      await plateState.fetchPlateData(); // 🔥 강제 fetch

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
