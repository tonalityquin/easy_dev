import 'package:flutter/material.dart';

import '../utils/buttons/monthly_animated_action_button.dart';
import '../monthly_plate_controller.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 15),
        MonthlyAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          onPressed: () async {
            if (widget.isEditMode) {
              await widget.controller.updatePlateEntry(
                context,
                widget.onStateRefresh, // ✅ 두 개만 전달
              );
            } else {
              await widget.controller.submitPlateEntry(
                context,
                widget.onStateRefresh, // ✅ 두 개만 전달
              );
            }
          },
        )
      ],
    );
  }
}
