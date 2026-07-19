import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_components.dart';

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
    return PromptButton(
      label: label,
      icon: isLocationSelected
          ? Icons.edit_location_alt_rounded
          : Icons.local_parking_rounded,
      variant: PromptButtonVariant.secondary,
      selected: isLocationSelected,
      expand: true,
      haptic: PromptHaptic.selection,
      onPressed: onPressed,
    );
  }
}
