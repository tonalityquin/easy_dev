import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ✅ OutlinedButton.icon 동일 디자인 공용 버튼
/// - StadiumBorder / minHeight 56 / border 1.4
/// - ✅ ColorScheme/TextTheme 기반
/// - 기존 Scale 애니메이션 + 로딩 스위처 유지
class MonthlyAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool enabled;
  final Future<void> Function() onPressed;

  final String? buttonLabel;
  final IconData? leadingIcon;

  const MonthlyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    this.enabled = true,
    this.buttonLabel,
    this.leadingIcon,
  });

  @override
  State<MonthlyAnimatedActionButton> createState() => _MonthlyAnimatedActionButtonState();
}

class _MonthlyAnimatedActionButtonState extends State<MonthlyAnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  static const _kAnim = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kAnim,
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  Future<void> _handleTap() async {
    HapticFeedback.selectionClick();
    await _controller.reverse();
    await _controller.forward();
    await widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ButtonStyle _buttonStyle(ColorScheme cs) {
    return ButtonStyle(
      minimumSize: const MaterialStatePropertyAll(Size.fromHeight(56)),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      shape: const MaterialStatePropertyAll(StadiumBorder()),
      elevation: const MaterialStatePropertyAll(0),
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return cs.surfaceVariant.withOpacity(.70);
        }
        return cs.surface;
      }),
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return cs.onSurface.withOpacity(.38);
        }
        return cs.primary;
      }),
      side: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return BorderSide(color: cs.outlineVariant.withOpacity(.85), width: 1.4);
        }
        return BorderSide(color: cs.primary.withOpacity(.45), width: 1.4);
      }),
      overlayColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.pressed)) {
          return cs.primary.withOpacity(.10);
        }
        return cs.primary.withOpacity(.06);
      }),
    );
  }

  TextStyle _labelStyle(BuildContext context, ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final base = tt.labelLarge ?? const TextStyle(fontSize: 14);
    return base.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: .2,
    );
  }


  Widget _buildIdleChild(BuildContext context, ColorScheme cs, String label) {
    final style = _labelStyle(context, cs);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(label, style: style),
      ],
    );
  }

  Widget _buildLoadingChild(BuildContext context, ColorScheme cs) {
    final style = _labelStyle(context, cs);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
        const SizedBox(width: 10),
        Text('처리 중...', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final String label = widget.buttonLabel ?? '정기 정산 생성';
    final bool isEnabled = widget.enabled && !widget.isLoading;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: OutlinedButton(
          onPressed: isEnabled ? _handleTap : null,
          style: _buttonStyle(cs),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: widget.isLoading
                ? KeyedSubtree(
              key: const ValueKey('loading'),
              child: _buildLoadingChild(context, cs),
            )
                : KeyedSubtree(
              key: const ValueKey('idle'),
              child: _buildIdleChild(context, cs, label),
            ),
          ),
        ),
      ),
    );
  }
}
