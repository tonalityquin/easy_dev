import 'package:flutter/material.dart';

class TripleModifyAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;
  final String? buttonLabel;

  const TripleModifyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<TripleModifyAnimatedActionButton> createState() => _TripleModifyAnimatedActionButtonState();
}

class _TripleModifyAnimatedActionButtonState extends State<TripleModifyAnimatedActionButton>
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
    await widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool isLoading = widget.isLoading;
    final bool isSelected = widget.isLocationSelected;

    final String label = widget.buttonLabel ?? (isSelected ? '입차 완료' : '입차 요청');

    // ✅ 브랜드 정책: 핵심 액션은 primary 계열로 통일
    final Color bg = isSelected ? cs.primary : cs.surface;
    final Color fg = isSelected ? cs.onPrimary : cs.onSurface;
    final BorderSide side = BorderSide(
      color: isSelected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.85),
      width: 1.2,
    );

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: isLoading ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: side,
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed) ? cs.outlineVariant.withOpacity(0.12) : null,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: isLoading
              ? SizedBox(
            key: const ValueKey('loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isSelected ? cs.onPrimary : cs.onSurface,
            ),
          )
              : Text(
            label,
            key: const ValueKey('buttonText'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
