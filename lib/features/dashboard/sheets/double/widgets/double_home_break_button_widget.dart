import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../double_home_dash_board_controller.dart';

class DoubleHomeBreakButtonWidget extends StatefulWidget {
  const DoubleHomeBreakButtonWidget({
    super.key,
    required this.controller,
  });

  final DoubleHomeDashBoardController controller;

  @override
  State<DoubleHomeBreakButtonWidget> createState() =>
      _DoubleHomeBreakButtonWidgetState();
}

class _DoubleHomeBreakButtonWidgetState
    extends State<DoubleHomeBreakButtonWidget> {
  bool _submitting = false;

  Future<void> _onTap() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.recordBreakTime(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonButton(
      label: '휴게 사용 확인',
      icon: Icons.coffee_rounded,
      onPressed: _submitting ? null : _onTap,
      loading: _submitting,
      expand: true,
      variant: CommonButtonVariant.secondary,
      haptic: CommonHaptic.light,
      semanticsLabel: '휴게 사용 확인',
    );
  }
}
