import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';

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
    return CommonButton(
      label: isLoading ? '처리 중' : buttonLabel,
      icon: leadingIcon,
      loading: isLoading,
      expand: true,
      variant: secondary
          ? CommonButtonVariant.secondary
          : CommonButtonVariant.primary,
      haptic: secondary ? CommonHaptic.selection : CommonHaptic.medium,
      onPressed: enabled && !isLoading ? onPressed : null,
    );
  }
}
