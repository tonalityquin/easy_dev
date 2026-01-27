import 'package:flutter/material.dart';

class DoubleModifyAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;
  final String? buttonLabel;

  const DoubleModifyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<DoubleModifyAnimatedActionButton> createState() => _DoubleModifyAnimatedActionButtonState();
}

class _DoubleModifyAnimatedActionButtonState extends State<DoubleModifyAnimatedActionButton>
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
    final bool isLocationSelected = widget.isLocationSelected;

    final String label = widget.buttonLabel ?? (isLocationSelected ? '입차 완료' : '입차 요청');

    // ✅ 메인 CTA는 primary로 통일 (전역 프리셋 반영)
    final bg = cs.primary;
    final fg = cs.onPrimary;

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
            side: BorderSide(color: cs.primary.withOpacity(0.25), width: 1.5),
          ),
          disabledBackgroundColor: cs.surfaceContainerLow,
          disabledForegroundColor: cs.onSurfaceVariant,
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed) ? cs.onPrimary.withOpacity(0.10) : null,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: isLoading
              ? SizedBox(
            key: const ValueKey('loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
              : Text(
            label,
            key: const ValueKey('buttonText'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
