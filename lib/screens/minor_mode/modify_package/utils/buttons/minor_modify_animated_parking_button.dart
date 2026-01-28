import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MinorModifyAnimatedParkingButton extends StatefulWidget {
  final bool isLocationSelected;
  final VoidCallback onPressed;
  final String? buttonLabel;

  const MinorModifyAnimatedParkingButton({
    super.key,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<MinorModifyAnimatedParkingButton> createState() =>
      _MinorModifyAnimatedParkingButtonState();
}

class _MinorModifyAnimatedParkingButtonState
    extends State<MinorModifyAnimatedParkingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  bool _tapBusy = false;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    )..value = 1.0;

    _scale = CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_tapBusy) return;
    setState(() => _tapBusy = true);

    try {
      HapticFeedback.selectionClick();

      await _pressCtrl.reverse();
      await _pressCtrl.forward();

      widget.onPressed();
    } finally {
      if (mounted) setState(() => _tapBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selected = widget.isLocationSelected;
    final label = (widget.buttonLabel ??
        (selected ? '구역 수정' : '주차 구역 선택'))
        .trim();

    final Color bg =
    selected ? cs.primaryContainer : cs.surfaceVariant.withOpacity(0.55);
    final Color fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    final Color border =
    selected ? cs.primary.withOpacity(0.65) : cs.outlineVariant.withOpacity(0.65);

    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _tapBusy ? null : _handleTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border, width: 1.4),
            ),
          ),
          child: Text(
            label.isEmpty ? (selected ? '구역 수정' : '주차 구역 선택') : label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
