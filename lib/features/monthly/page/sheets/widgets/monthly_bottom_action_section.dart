import 'package:flutter/material.dart';

import '../../../controllers/monthly_plate_controller.dart';
import '../../widgets/monthly_animated_action_button.dart';

class MonthlyBottomActionSection extends StatelessWidget {
  const MonthlyBottomActionSection({
    super.key,
    required this.controller,
    required this.onStateRefresh,
    this.isEditMode = false,
  });

  final MonthlyPlateController controller;
  final VoidCallback onStateRefresh;
  final bool isEditMode;

  @override
  Widget build(BuildContext context) {
    return MonthlyAnimatedActionButton(
      isLoading: controller.isLoading,
      enabled: !controller.isLoading,
      buttonLabel: isEditMode ? '수정 저장' : '정기권 생성',
      leadingIcon:
          isEditMode ? Icons.save_outlined : Icons.add_circle_outline_rounded,
      onPressed: () async {
        if (isEditMode) {
          await controller.updatePlateEntry(context, onStateRefresh);
        } else {
          await controller.submitPlateEntry(context, onStateRefresh);
        }
      },
    );
  }
}
