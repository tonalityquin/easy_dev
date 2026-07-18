import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';

class UpdateAlertBar extends StatelessWidget {
  const UpdateAlertBar({
    super.key,
    required this.onTapUpdate,
  });

  final VoidCallback onTapUpdate;

  @override
  Widget build(BuildContext context) {
    return PromptButton(
      label: '업데이트',
      icon: Icons.new_releases_rounded,
      onPressed: onTapUpdate,
      variant: PromptButtonVariant.secondary,
      expand: true,
      haptic: PromptHaptic.selection,
      minHeight: 52,
      semanticsLabel: '업데이트 내역 열기',
    );
  }
}
