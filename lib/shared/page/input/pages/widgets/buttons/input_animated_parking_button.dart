import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_components.dart';

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
    return PromptButton(
      label: label,
      icon: isLocationSelected
          ? Icons.restart_alt_rounded
          : Icons.local_parking_rounded,
      variant: PromptButtonVariant.secondary,
      selected: isLocationSelected,
      expand: true,
      haptic: PromptHaptic.selection,
      onPressed: onPressed,
    );
  }
}
