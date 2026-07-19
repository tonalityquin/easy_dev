import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_components.dart';

class ModifyAnimatedPhotoButton extends StatelessWidget {
  const ModifyAnimatedPhotoButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PromptButton(
      label: '사진 촬영',
      icon: Icons.photo_camera_rounded,
      variant: PromptButtonVariant.secondary,
      expand: true,
      haptic: PromptHaptic.selection,
      onPressed: onPressed,
    );
  }
}
