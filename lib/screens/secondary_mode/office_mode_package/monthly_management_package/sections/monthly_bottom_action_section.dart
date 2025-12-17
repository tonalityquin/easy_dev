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
    final String label = widget.isEditMode ? '수정' : '정기 정산 생성';
    final IconData icon = widget.isEditMode ? Icons.save_outlined : Icons.add_circle_outline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),

        // ✅ 결제 버튼과 동일한 Outlined 스타일 버튼
        MonthlyAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          enabled: true, // isLoading으로 자동 disable 처리됨
          buttonLabel: label,
          leadingIcon: icon,
          onPressed: () async {
            if (widget.isEditMode) {
              await widget.controller.updatePlateEntry(
                context,
                widget.onStateRefresh,
              );
            } else {
              await widget.controller.submitPlateEntry(
                context,
                widget.onStateRefresh,
              );
            }
          },
        ),
      ],
    );
  }
}
