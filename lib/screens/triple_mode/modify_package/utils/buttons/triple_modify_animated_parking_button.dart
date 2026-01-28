import 'package:flutter/material.dart';

class TripleModifyAnimatedParkingButton extends StatefulWidget {
  final bool isLocationSelected;
  final VoidCallback onPressed;
  final String? buttonLabel;

  const TripleModifyAnimatedParkingButton({
    super.key,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<TripleModifyAnimatedParkingButton> createState() => _TripleModifyAnimatedParkingButtonState();
}

class _TripleModifyAnimatedParkingButtonState extends State<TripleModifyAnimatedParkingButton>
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
    final label = widget.buttonLabel ?? (isSelected ? '구역 수정' : '주차 구역 선택');

    // ✅ 보조 버튼: surface 기반 + 선택 시 primary 강조
    final Color bg = cs.surface;
    final Color fg = isSelected ? cs.primary : cs.onSurface;
    final BorderSide side = BorderSide(
      color: isSelected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.85),
      width: 1.2,
    );

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
            side: side,
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed) ? cs.outlineVariant.withOpacity(0.12) : null,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
