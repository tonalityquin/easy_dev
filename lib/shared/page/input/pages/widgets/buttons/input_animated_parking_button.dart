import 'package:flutter/material.dart';

import '../../../../../../design_system/common_ui/common_ui_components.dart';

class InputAnimatedParkingButton extends StatelessWidget {
  final bool isLocationSelected;
  final VoidCallback onPressed;
  final String? buttonLabel;

  const InputAnimatedParkingButton({
    super.key,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = buttonLabel ??
        (isLocationSelected ? '구역 초기화' : '주차 구역 선택');
    return CommonButton(
      label: label,
      icon: isLocationSelected
          ? Icons.restart_alt_rounded
          : Icons.local_parking_rounded,
      variant: CommonButtonVariant.secondary,
      selected: isLocationSelected,
      expand: true,
      haptic: CommonHaptic.selection,
      onPressed: onPressed,
    );
  }
}
