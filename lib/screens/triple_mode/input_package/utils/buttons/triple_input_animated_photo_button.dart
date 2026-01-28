import 'package:flutter/material.dart';

class TripleInputAnimatedPhotoButton extends StatefulWidget {
  final VoidCallback onPressed;

  const TripleInputAnimatedPhotoButton({super.key, required this.onPressed});

  @override
  State<TripleInputAnimatedPhotoButton> createState() =>
      _TripleInputAnimatedPhotoButtonState();
}

class _TripleInputAnimatedPhotoButtonState extends State<TripleInputAnimatedPhotoButton>
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

    // ✅ 사진 버튼은 “중립 + 약한 강조”로 통일 (secondaryContainer 사용)
    final bg = cs.secondaryContainer;
    final fg = cs.onSecondaryContainer;
    final side = BorderSide(color: cs.secondary.withOpacity(0.55), width: 1.2);

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
                (states) => states.contains(MaterialState.pressed)
                ? cs.secondary.withOpacity(0.10)
                : null,
          ),
        ),
        child: const Text(
          '사진 촬영',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
