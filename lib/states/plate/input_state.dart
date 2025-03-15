import 'package:flutter/material.dart';
import '../../utils/show_snackbar.dart';
import '../area/area_state.dart';
import '../user/user_state.dart';
import '../../repositories/plate/plate_repository.dart';
import 'dart:developer' as dev;

class InputState with ChangeNotifier {
  final PlateRepository _plateRepository;

  InputState(this._plateRepository);

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
        return true; // 중복 발견 → 입차 불가
      }
    }
    return false; // 중복 없음 → 입차 가능
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
  }) async {
    // 🔍 입차 요청 전 중복 확인
    if (await isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      showSnackbar(context, '이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    if (location.isEmpty) {
      location = '미지정';
    }

    final collection = isLocationSelected ? 'parking_completed' : 'parking_requests';
    final type = isLocationSelected ? '입차 완료' : '입차 요청';

    try {
      await _plateRepository.addRequestOrCompleted(
        collection: collection,
        plateNumber: plateNumber,
        location: location,
        area: areaState.currentArea,
        userName: userState.name,
        type: type,
        adjustmentType: adjustmentType,
        statusList: statusList ?? [],
        basicStandard: basicStandard,
        basicAmount: basicAmount,
        addStandard: addStandard,
        addAmount: addAmount,
      );

      showSnackbar(context, '$type 완료');
      notifyListeners();
    } catch (error) {
      showSnackbar(context, '오류 발생: $error');
    }
  }
}
