import 'package:flutter/material.dart';
import '../../models/plate_model.dart';
import '../../models/plate_log_model.dart';
import '../../utils/snackbar_helper.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import 'log_plate.dart';
import '../../repositories/plate/plate_repository.dart';
import 'dart:developer' as dev;

class InputPlate with ChangeNotifier {
  final PlateRepository _plateRepository;
  final LogPlateState _logState; // ✅ 로그 주입

  InputPlate(this._plateRepository, this._logState);

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
    List<String>? imageUrls,
    int? lockedFee,
    bool isLockedFee = false,               // ✅ 추가
    int? lockedAtTimeInSeconds,            // ✅ 추가
  }) async {
    if (await isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
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
        imageUrls: imageUrls,
        isLockedFee: isLockedFee,
        lockedAtTimeInSeconds: lockedAtTimeInSeconds,
    );

      // ✅ 로그 저장
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

      notifyListeners();
    } catch (error) {
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
    bool? isLockedFee,
    int? lockedAtTimeInSeconds,
  }) async {
    try {
      final documentId = '${plate.plateNumber}_${plate.area}';

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
      );

      await _plateRepository.addOrUpdateDocument(
        collectionKey,
        documentId,
        updatedPlate.toMap(),
      );

      // ✅ 정산 변경 여부 감지 후 로그 저장
      if ((plate.isLockedFee != updatedPlate.isLockedFee)) {
        final actionLog = updatedPlate.isLockedFee
            ? '사전 정산 완료'
            : '사전 정산 취소';

        await _logState.saveLog(
          PlateLogModel(
            plateNumber: plate.plateNumber,
            area: plate.area,
            from: collectionKey,
            to: collectionKey,
            action: actionLog,
            performedBy: userState.name,
            timestamp: DateTime.now(),
          ),
        );
      }

      showSuccessSnackbar(context, '정보 수정 완료');
      notifyListeners();

      return true;
    } catch (e) {
      showFailedSnackbar(context, '정보 수정 실패: $e');
      return false;
    }
  }
}
