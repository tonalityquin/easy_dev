import 'package:flutter/material.dart';

class MinorInputAnimatedParkingButton extends StatefulWidget {
  final bool isLocationSelected;
  final VoidCallback onPressed;
  final String? buttonLabel;

  const MinorInputAnimatedParkingButton({
    super.key,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<MinorInputAnimatedParkingButton> createState() => _MinorInputAnimatedParkingButtonState();
}

class _MinorInputAnimatedParkingButtonState extends State<MinorInputAnimatedParkingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  Future<void> _handleTap() async {
    await _controller.reverse();
    await _controller.forward();
    widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isSelected = widget.isLocationSelected;
    final label = widget.buttonLabel ?? (isSelected ? '구역 초기화' : '주차 구역 선택');

    final Color bg = isSelected ? cs.primaryContainer : cs.surface;
    final Color fg = isSelected ? cs.onPrimaryContainer : cs.onSurface;
    final Color border = isSelected ? cs.primary : cs.outlineVariant;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: border, width: 1.5),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
