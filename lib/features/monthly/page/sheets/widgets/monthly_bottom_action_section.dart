import 'package:flutter/material.dart';

import '../../../controllers/monthly_plate_controller.dart';
import '../../widgets/monthly_animated_action_button.dart';

class MonthlyBottomActionSection extends StatefulWidget {
  final MonthlyPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;
  final bool isEditMode;

  const MonthlyBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
    this.isEditMode = false,
  });

  @override
  State<MonthlyBottomActionSection> createState() => _MonthlyBottomActionSectionState();
}

class _MonthlyBottomActionSectionState extends State<MonthlyBottomActionSection> {
  @override
  Widget build(BuildContext context) {
    final label = widget.isEditMode ? '수정 저장' : '정기권 생성';
    final icon = widget.isEditMode ? Icons.save_outlined : Icons.add_circle_outline;

    return MonthlyAnimatedActionButton(
      isLoading: widget.controller.isLoading,
      enabled: !widget.controller.isLoading,
      buttonLabel: label,
      leadingIcon: icon,
      onPressed: () async {
        if (widget.isEditMode) {
          await widget.controller.updatePlateEntry(context, widget.onStateRefresh);
        } else {
          await widget.controller.submitPlateEntry(context, widget.onStateRefresh);
        }
      },
    );
  }
}
