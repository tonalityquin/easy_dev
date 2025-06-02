import 'package:flutter/material.dart';

class InputAnimatedPhotoButton extends StatefulWidget {
  final VoidCallback onPressed;

  const InputAnimatedPhotoButton({super.key, required this.onPressed});

  @override
  State<InputAnimatedPhotoButton> createState() => _InputAnimatedPhotoButtonState();
}

class _InputAnimatedPhotoButtonState extends State<InputAnimatedPhotoButton> with SingleTickerProviderStateMixin {
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
    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[50],
          foregroundColor: Colors.green[800],
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.green, width: 1.5),
          ),
        ),
        child: const Text(
          '사진 촬영',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
