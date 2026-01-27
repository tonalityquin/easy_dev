import 'package:flutter/material.dart';

class DoubleInputAnimatedPhotoButton extends StatefulWidget {
  final VoidCallback onPressed;

  const DoubleInputAnimatedPhotoButton({super.key, required this.onPressed});

  @override
  State<DoubleInputAnimatedPhotoButton> createState() => _DoubleInputAnimatedPhotoButtonState();
}

class _DoubleInputAnimatedPhotoButtonState extends State<DoubleInputAnimatedPhotoButton>
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

    // ✅ 사진 버튼은 “보조 액션” → tertiary 계열로 분리(브랜드 프리셋 반영)
    final bg = cs.tertiaryContainer;
    final fg = cs.onTertiaryContainer;
    final border = cs.tertiary.withOpacity(0.55);

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
                (states) => states.contains(MaterialState.pressed) ? cs.tertiary.withOpacity(0.08) : null,
          ),
        ),
        child: const Text(
          '사진 촬영',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
