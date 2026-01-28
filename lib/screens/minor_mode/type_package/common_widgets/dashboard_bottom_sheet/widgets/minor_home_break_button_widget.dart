import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../minor_home_dash_board_controller.dart';

class MinorHomeBreakButtonWidget extends StatefulWidget {
  final MinorHomeDashBoardController controller;

  const MinorHomeBreakButtonWidget({super.key, required this.controller});

  @override
  State<MinorHomeBreakButtonWidget> createState() => _MinorHomeBreakButtonWidgetState();
}

class _MinorHomeBreakButtonWidgetState extends State<MinorHomeBreakButtonWidget> {
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
          valueColor: AlwaysStoppedAnimation<Color>(cs.onSurface),
        ),
      )
          : const Icon(Icons.coffee),
      label: const Text(
        '휴게 사용 확인',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        elevation: 0,
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ).copyWith(
        overlayColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => states.contains(MaterialState.pressed)
              ? cs.outlineVariant.withOpacity(0.12)
              : null,
        ),
      ),
    );
  }
}
