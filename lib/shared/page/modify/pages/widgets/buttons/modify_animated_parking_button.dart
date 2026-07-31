import 'package:flutter/material.dart';

import '../../../../../../design_system/common_ui/common_ui_components.dart';

class ModifyAnimatedParkingButton extends StatelessWidget {
  const ModifyAnimatedParkingButton({
    super.key,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  final bool isLocationSelected;
  final VoidCallback onPressed;
  final String? buttonLabel;

  @override
  Widget build(BuildContext context) {
    final label = buttonLabel ??
        (isLocationSelected ? '주차 구역 변경' : '주차 구역 선택');
    return CommonButton(
      label: label,
      icon: isLocationSelected
          ? Icons.edit_location_alt_rounded
          : Icons.local_parking_rounded,
      variant: CommonButtonVariant.secondary,
      selected: isLocationSelected,
      expand: true,
      haptic: CommonHaptic.selection,
      onPressed: onPressed,
    );
  }
}
