import 'package:flutter/material.dart';

import '../../../../../../design_system/common_ui/common_ui_components.dart';

class ModifyAnimatedPhotoButton extends StatelessWidget {
  const ModifyAnimatedPhotoButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

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
