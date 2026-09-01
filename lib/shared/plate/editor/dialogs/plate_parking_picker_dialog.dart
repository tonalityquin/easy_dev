import 'package:flutter/material.dart';

import '../widgets/plate_parking_picker_content.dart';
import 'plate_editor_dialog.dart';

Future<String?> showPlateParkingPickerDialog({
  required BuildContext context,
  required String currentLocation,
  required List<String> preferredParkingAreas,
  String? areaOverride,
  ValueChanged<String>? onDebug,
  VoidCallback? onInvalidAreaConfiguration,
}) async {
  String? picked;
  var invalidAreaConfiguration = false;
  final normalizedArea = areaOverride?.trim() ?? '';
  onDebug?.call(
    'parking_picker=open presentation=plate_editor_dialog size=wide area=${normalizedArea.isEmpty ? "current" : normalizedArea}',
  );

  try {
    await showPlateEditorDialog<void>(
      context: context,
      barrierLabel: '주차 위치',
      size: PlateEditorDialogSize.wide,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PlateParkingPickerContent(
          currentLocation: currentLocation,
          preferredParkingAreas: preferredParkingAreas,
          areaOverride: areaOverride,
          onLocationApplied: (value) {
            final normalized = value.trim();
            picked = normalized;
            onDebug?.call(
              'parking_picker=selected location=$normalized area=${normalizedArea.isEmpty ? "current" : normalizedArea}',
            );
          },
          onExit: () {
            final navigator = Navigator.of(dialogContext);
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
          onInvalidAreaConfiguration: () {
            invalidAreaConfiguration = true;
            onDebug?.call(
              'parking_picker=invalid_area_configuration action=close_picker_then_host',
            );
            final navigator = Navigator.of(dialogContext);
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
          onDebug: (message) {
            onDebug?.call('parking_picker_workspace $message');
          },
        );
      },
    );
  } catch (error, stackTrace) {
    onDebug?.call('parking_picker=error error=$error');
    onDebug?.call('parking_picker=stack_trace $stackTrace');
    rethrow;
  }

  if (invalidAreaConfiguration) {
    onDebug?.call(
      'parking_picker=closed result=invalid_area_configuration action=close_host',
    );
    onInvalidAreaConfiguration?.call();
    return null;
  }

  final result = picked?.trim() ?? '';
  if (result.isEmpty) {
    onDebug?.call('parking_picker=closed result=cancelled');
    return null;
  }
  onDebug?.call('parking_picker=closed result=selected location=$result');
  return result;
}
