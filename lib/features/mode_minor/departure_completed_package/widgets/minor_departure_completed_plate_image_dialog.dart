import 'package:flutter/material.dart';

import '../../../../shared/page/modify/application/modify_plate_service.dart';
import '../../../../shared/plate/widgets/stored_plate_photo_list_screen.dart';

Future<T?> showMinorDepartureCompletedPlateImageDialog<T>(
  BuildContext context, {
  required String plateNumber,
}) {
  return showStoredPlatePhotoDialog<T>(
    context: context,
    child: MinorDepartureCompletedPlateImageDialog(plateNumber: plateNumber),
  );
}

class MinorDepartureCompletedPlateImageDialog extends StatelessWidget {
  const MinorDepartureCompletedPlateImageDialog({
    super.key,
    required this.plateNumber,
  });

  final String plateNumber;

  @override
  Widget build(BuildContext context) {
    return StoredPlatePhotoListScreen(
      plateNumber: plateNumber,
      diagnosticSource: 'minor_departure_completed',
      loadPhotos: (loadContext, yearMonth, onDebug) {
        return ModifyPlateService.listStoredPlateImages(
          context: loadContext,
          plateNumber: plateNumber,
          yearMonth: yearMonth,
          onDebug: onDebug,
        );
      },
    );
  }
}
