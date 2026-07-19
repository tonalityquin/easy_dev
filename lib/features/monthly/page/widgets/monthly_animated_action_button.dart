import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';

class MonthlyAnimatedActionButton extends StatelessWidget {
  const MonthlyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.enabled,
    required this.buttonLabel,
    required this.onPressed,
    this.leadingIcon,
  });

  final bool isLoading;
  final bool enabled;
  final String buttonLabel;
  final Future<void> Function() onPressed;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final secondary = buttonLabel.contains('결제 화면');
    return PromptButton(
      label: isLoading ? '처리 중' : buttonLabel,
      icon: leadingIcon,
      loading: isLoading,
      expand: true,
      variant: secondary
          ? PromptButtonVariant.secondary
          : PromptButtonVariant.primary,
      haptic: secondary ? PromptHaptic.selection : PromptHaptic.medium,
      onPressed: enabled && !isLoading ? onPressed : null,
    );
  }
}
