import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../double_home_dash_board_controller.dart';

class DoubleHomeBreakButtonWidget extends StatefulWidget {
  final DoubleHomeDashBoardController controller;

  const DoubleHomeBreakButtonWidget({super.key, required this.controller});

  @override
  State<DoubleHomeBreakButtonWidget> createState() => _DoubleHomeBreakButtonWidgetState();
}

class _DoubleHomeBreakButtonWidgetState extends State<DoubleHomeBreakButtonWidget> {
  bool _submitting = false;

  Future<void> _onTap() async {
    if (_submitting) return;

    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      await widget.controller.recordBreakTime(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.icon(
      onPressed: _submitting ? null : _onTap,
      icon: _submitting
          ? SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      )
          : const Icon(Icons.coffee),
      label: const Text(
        '휴게 사용 확인',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.9), width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ).copyWith(
        overlayColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => states.contains(MaterialState.pressed) ? cs.outlineVariant.withOpacity(0.18) : null,
        ),
      ),
    );
  }
}
