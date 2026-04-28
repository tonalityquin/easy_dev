import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../features/account/applications/user_state.dart';
import '../../../../../shared/plate/application/common/delete_plate.dart';
import '../../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../../shared/plate/widgets/plate_remove_dialog.dart';

Future<bool> showParkingCompletedDeleteDialog(
  BuildContext context,
  PlateModel plate,
) async {
  final deleter = context.read<DeletePlate>();
  final performedBy = context.read<UserState>().name;

  final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => PlateRemoveDialog(
          onConfirm: () {
            Navigator.of(dialogContext).pop(true);
          },
        ),
      ) ??
      false;

  if (!confirmed) return false;

  try {
    final t = plate.typeEnum;

    if (t == PlateType.parkingRequests) {
      await deleter.deleteFromParkingRequest(
        plate.plateNumber,
        plate.area,
        performedBy: performedBy,
      );
    } else if (t == PlateType.parkingCompleted) {
      await deleter.deleteFromParkingCompleted(
        plate.plateNumber,
        plate.area,
        performedBy: performedBy,
      );
    } else if (t == PlateType.departureRequests) {
      await deleter.deleteFromDepartureRequest(
        plate.plateNumber,
        plate.area,
        performedBy: performedBy,
      );
    } else {
      return false;
    }

    return true;
  } catch (_) {
    return false;
  }
}

Future<void> appendParkingCompletedPlateLog({
  required BuildContext context,
  required String plateId,
  required Map<String, dynamic> log,
}) async {
  final repo = context.read<PlateRepository>();
  await repo.appendPlateLog(
    plateId: plateId,
    log: log,
  );
}

String resolveParkingCompletedDocId(PlateModel plate) {
  if (plate.id.trim().isNotEmpty) return plate.id.trim();
  return '${plate.plateNumber}_${plate.area}';
}

String resolveParkingCompletedEffectiveLocation(
  PlateModel plate, {
  String fallback = '미지정',
}) {
  final location = plate.location.trim();
  return location.isEmpty ? fallback : location;
}

String resolveParkingCompletedStatusMemo(PlateModel plate) {
  final customStatus = (plate.customStatus ?? '').trim();
  if (customStatus.isNotEmpty) return customStatus;

  final list = plate.statusList;
  if (list.isNotEmpty) {
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');
  }

  return '';
}

void reportParkingCompletedDbSafe({
  required String area,
  required String action,
  required String source,
  int n = 1,
}) {
  try {} catch (_) {}
}

Future<void> handleParkingCompletedEntryRequest(
  BuildContext context,
  String plateNumber,
  String area,
) async {
  final movementPlate = context.read<MovementPlate>();
  await movementPlate.goBackToParkingRequest(
    fromType: PlateType.parkingCompleted,
    plateNumber: plateNumber,
    area: area,
    newLocation: '미지정',
  );
}

Future<void> handleParkingCompletedBackToCompletedRequest(
  BuildContext context, {
  required PlateModel plate,
  String? fallbackArea,
  String fallbackLocation = '미지정',
}) async {
  final movementPlate = context.read<MovementPlate>();
  final area =
      plate.area.trim().isNotEmpty ? plate.area.trim() : (fallbackArea ?? '').trim();
  final location =
      resolveParkingCompletedEffectiveLocation(plate, fallback: fallbackLocation);
  await movementPlate.goBackToParkingCompleted(
    plate.plateNumber,
    area,
    location,
  );
}
