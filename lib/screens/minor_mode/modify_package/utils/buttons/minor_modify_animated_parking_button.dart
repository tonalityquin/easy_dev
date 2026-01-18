import 'package:flutter/material.dart';

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
  State<MinorModifyAnimatedParkingButton> createState() => _MinorModifyAnimatedParkingButtonState();
}

class _MinorModifyAnimatedParkingButtonState extends State<MinorModifyAnimatedParkingButton> with SingleTickerProviderStateMixin {
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

  void _handleTap() async {
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
    final isSelected = widget.isLocationSelected;

    final label = widget.buttonLabel ?? (isSelected ? '구역 수정' : '주차 구역 선택');

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.indigo[50] : Colors.blueGrey[50],
          foregroundColor: isSelected ? Colors.indigo[800] : Colors.blueGrey[800],
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? Colors.indigo : Colors.blueGrey,
              width: 1.5,
            ),
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
