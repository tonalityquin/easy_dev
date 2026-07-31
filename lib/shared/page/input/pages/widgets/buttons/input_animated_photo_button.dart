import 'package:flutter/material.dart';

import '../../../../../../design_system/common_ui/common_ui_components.dart';

class InputAnimatedPhotoButton extends StatelessWidget {
  final VoidCallback onPressed;

  const InputAnimatedPhotoButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CommonButton(
      label: '사진 촬영',
      icon: Icons.photo_camera_rounded,
      variant: CommonButtonVariant.secondary,
      expand: true,
      haptic: CommonHaptic.selection,
      onPressed: onPressed,
    );
  }
}
