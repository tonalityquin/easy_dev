import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_components.dart';

class InputAnimatedActionButton extends StatelessWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final bool isMinorMode;
  final Future<void> Function() onPressed;

  const InputAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.isMinorMode,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final requestMode = isMinorMode && !isLocationSelected;
    final disabled = isLoading || (!isMinorMode && !isLocationSelected);
    return PromptButton(
      label: requestMode ? '입차 요청' : '입차 완료',
      icon: requestMode
          ? Icons.outbox_rounded
          : Icons.check_circle_outline_rounded,
      loading: isLoading,
      expand: true,
      haptic: PromptHaptic.medium,
      onPressed: disabled ? null : onPressed,
    );
  }
}
