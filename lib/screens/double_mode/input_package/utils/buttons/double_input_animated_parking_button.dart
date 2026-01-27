import 'package:flutter/material.dart';

class DoubleInputAnimatedParkingButton extends StatefulWidget {
  final bool isLocationSelected;
  final VoidCallback onPressed;
  final String? buttonLabel;

  const DoubleInputAnimatedParkingButton({
    super.key,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<DoubleInputAnimatedParkingButton> createState() => _DoubleInputAnimatedParkingButtonState();
}

class _DoubleInputAnimatedParkingButtonState extends State<DoubleInputAnimatedParkingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    );
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
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

    // ✅ 선택 여부에 따라 “강조/중립” 톤만 바꿈 (하드코딩 팔레트 제거)
    final bg = isSelected ? cs.primary.withOpacity(0.10) : cs.surface;
    final fg = isSelected ? cs.primary : cs.onSurface;
    final border = isSelected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.85);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: OutlinedButton(
        onPressed: _handleTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: border, width: 1.5),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed) ? cs.primary.withOpacity(0.08) : null,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
