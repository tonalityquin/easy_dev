import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MonthlyAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final Future<void> Function() onPressed;
  final String? buttonLabel;

  const MonthlyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<MonthlyAnimatedActionButton> createState() =>
      _MonthlyAnimatedActionButtonState();
}

class _MonthlyAnimatedActionButtonState
    extends State<MonthlyAnimatedActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // 버튼 살짝 눌리는 스케일 애니메이션(0.95 ↔ 1.0)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0, // ✅ 초기값을 상한으로 지정(범위 밖 값 방지)
    );
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  Future<void> _handleTap() async {
    HapticFeedback.selectionClick();
    await _controller.reverse(); // 1.0 → 0.95
    await _controller.forward(); // 0.95 → 1.0
    await widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ButtonStyle _buttonStyle(ColorScheme cs) {
    // 톤 다운 배경 + 선(primary) + 텍스트(onPrimaryContainer)
    return ButtonStyle(
      elevation: const MaterialStatePropertyAll(0),
      minimumSize: const MaterialStatePropertyAll(Size(0, 56)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(vertical: 16.0, horizontal: 80),
      ),
      shape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return cs.surfaceVariant; // 비활성 배경
        }
        if (states.contains(MaterialState.pressed)) {
          return cs.primaryContainer.withOpacity(.92); // 눌림 톤
        }
        return cs.primaryContainer; // 기본 톤(라이트)
      }),
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return cs.onSurface.withOpacity(.38); // 비활성 텍스트
        }
        return cs.onPrimaryContainer; // 기본 텍스트
      }),
      side: MaterialStateProperty.resolveWith((states) {
        final color = states.contains(MaterialState.disabled)
            ? cs.outlineVariant
            : cs.primary;
        return BorderSide(color: color, width: 1.5);
      }),
      overlayColor: MaterialStatePropertyAll(cs.primary.withOpacity(.06)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String label = widget.buttonLabel ?? '정기 정산 생성';

    return Semantics(
      button: true,
      enabled: !widget.isLoading,
      label: label,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ElevatedButton(
          onPressed: widget.isLoading ? null : _handleTap,
          style: _buttonStyle(cs),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: widget.isLoading
                ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  cs.onPrimaryContainer,
                ),
              ),
            )
                : Text(
              key: const ValueKey('buttonText'),
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
