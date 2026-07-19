import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_components.dart';

class ModifyAnimatedActionButton extends StatelessWidget {
  const ModifyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;
  final String? buttonLabel;

  @override
  Widget build(BuildContext context) {
    final label = buttonLabel ?? '수정 완료';
    return PromptButton(
      label: label,
      icon: Icons.save_rounded,
      loading: isLoading,
      expand: true,
      semanticsLabel: isLocationSelected
          ? '$label, 주차 구역 선택됨'
          : '$label, 주차 구역 미선택',
      haptic: PromptHaptic.medium,
      onPressed: isLoading ? null : onPressed,
    );
  }
}
