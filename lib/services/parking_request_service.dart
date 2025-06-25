import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../enums/plate_type.dart';
import '../states/plate/plate_state.dart';
import '../states/plate/delete_plate.dart';
import '../states/plate/movement_plate.dart';
import '../states/user/user_state.dart';
import '../repositories/plate/plate_repository.dart';
import '../models/plate_model.dart';
import '../utils/snackbar_helper.dart';

class ParkingRequestService {
  final BuildContext context;

  ParkingRequestService(this.context);

  void togglePlateSelection(String plateNumber) {
    final userName = context.read<UserState>().name;
    context.read<PlateState>().toggleIsSelected(
          collection: PlateType.parkingRequests,
          plateNumber: plateNumber,
          userName: userName,
          onError: (msg) => showFailedSnackbar(context, msg),
        );
  }

  Future<void> completeParking({
    required PlateModel selectedPlate,
    required String location,
  }) async {
    final userState = context.read<UserState>();
    final plateState = context.read<PlateState>();
    final movementPlate = context.read<MovementPlate>();
    final plateRepo = context.read<PlateRepository>();

    try {
      await plateRepo.addRequestOrCompleted(
        plateNumber: selectedPlate.plateNumber,
        location: location,
        area: selectedPlate.area,
        userName: userState.name,
        plateType: PlateType.parkingCompleted,
        // ✅ type으로 구분
        billingType: null,
        statusList: [],
        basicStandard: 0,
        basicAmount: 0,
        addStandard: 0,
        addAmount: 0,
        region: selectedPlate.region ?? '전국',
      );

      movementPlate.setParkingCompleted(
        selectedPlate.plateNumber,
        selectedPlate.area,
        plateState,
        location,
      );

      if (!context.mounted) return;
      showSuccessSnackbar(context, '입차 완료: ${selectedPlate.plateNumber} ($location)');
    } catch (e) {
      debugPrint('입차 완료 실패: $e');
      if (!context.mounted) return;
      showFailedSnackbar(context, '입차 완료 중 오류 발생: $e');
    }
  }

  void deletePlate(PlateModel plate) {
    context.read<DeletePlate>().deleteFromParkingRequest(
          plate.plateNumber,
          plate.area,
        );
    showSuccessSnackbar(context, '삭제 완료: ${plate.plateNumber}');
  }
}
