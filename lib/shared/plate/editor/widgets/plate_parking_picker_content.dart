import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../workspaces/plate_parking_workspace.dart';

class PlateParkingPickerContent extends StatelessWidget {
  const PlateParkingPickerContent({
    super.key,
    required this.currentLocation,
    required this.preferredParkingAreas,
    required this.onLocationApplied,
    required this.onExit,
    this.onInvalidAreaConfiguration,
    this.areaOverride,
    this.onClearLocation,
    this.onDebug,
  });

  final String currentLocation;
  final List<String> preferredParkingAreas;
  final ValueChanged<String> onLocationApplied;
  final VoidCallback onExit;
  final VoidCallback? onInvalidAreaConfiguration;
  final String? areaOverride;
  final VoidCallback? onClearLocation;
  final ValueChanged<String>? onDebug;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CommonUiTheme.of(context).borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: PlateParkingWorkspace(
        currentLocation: currentLocation,
        preferredParkingAreas: preferredParkingAreas,
        areaOverride: areaOverride,
        onLocationApplied: onLocationApplied,
        onClearLocation: onClearLocation,
        onExit: onExit,
        onInvalidAreaConfiguration: onInvalidAreaConfiguration,
        onDebug: onDebug,
      ),
    );
  }
}
