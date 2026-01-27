import 'package:flutter/material.dart';

class DoubleModifyAnimatedPhotoButton extends StatefulWidget {
  final VoidCallback onPressed;

  const DoubleModifyAnimatedPhotoButton({super.key, required this.onPressed});

  @override
  State<DoubleModifyAnimatedPhotoButton> createState() => _DoubleModifyAnimatedPhotoButtonState();
}

class _DoubleModifyAnimatedPhotoButtonState extends State<DoubleModifyAnimatedPhotoButton>
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
    final cs = Theme.of(context).colorScheme;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.tertiaryContainer.withOpacity(0.55),
          foregroundColor: cs.tertiary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.tertiary.withOpacity(0.55), width: 1.5),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed) ? cs.tertiary.withOpacity(0.10) : null,
          ),
        ),
        child: const Text(
          '사진 촬영',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
