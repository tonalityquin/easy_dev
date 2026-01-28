import 'package:flutter/material.dart';

class TripleInputAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;

  const TripleInputAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
  });

  @override
  State<TripleInputAnimatedActionButton> createState() =>
      _TripleInputAnimatedActionButtonState();
}

class _TripleInputAnimatedActionButtonState extends State<TripleInputAnimatedActionButton>
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

    // ✅ Normal 모드: "입차 완료"만 노출
    const String label = '입차 완료';

    // ✅ 위치 미선택이면 완료 불가(입차요청 플로우 제거)
    final bool disabled = widget.isLoading || !widget.isLocationSelected;

    // ✅ 브랜드 톤: enabled는 primary / disabled는 surfaceVariant 계열
    final Color bg = disabled ? cs.surfaceContainerLow : cs.primary;
    final Color fg = disabled ? cs.onSurfaceVariant : cs.onPrimary;
    final BorderSide side = BorderSide(
      color: disabled ? cs.outlineVariant.withOpacity(0.85) : cs.primary.withOpacity(0.65),
      width: 1.2,
    );

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: disabled ? null : _handleTap,
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
                (states) => states.contains(MaterialState.pressed)
                ? cs.onPrimary.withOpacity(0.10)
                : null,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: widget.isLoading
              ? SizedBox(
            key: const ValueKey('loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fg,
            ),
          )
              : const Text(
            key: ValueKey('buttonText'),
            label,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
