import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../triple_home_dash_board_controller.dart';

class TripleHomeBreakButtonWidget extends StatefulWidget {
  const TripleHomeBreakButtonWidget({
    super.key,
    required this.controller,
  });

  final TripleHomeDashBoardController controller;

  @override
  State<TripleHomeBreakButtonWidget> createState() =>
      _TripleHomeBreakButtonWidgetState();
}

class _TripleHomeBreakButtonWidgetState
    extends State<TripleHomeBreakButtonWidget> {
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
    return PromptButton(
      label: '휴게 사용 확인',
      icon: Icons.coffee_rounded,
      onPressed: _submitting ? null : _onTap,
      loading: _submitting,
      expand: true,
      variant: PromptButtonVariant.secondary,
      haptic: PromptHaptic.light,
      semanticsLabel: '휴게 사용 확인',
    );
  }
}
