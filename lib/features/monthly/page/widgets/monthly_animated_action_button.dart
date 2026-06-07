import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _actionInk = Color(0xFF101828);
const _actionLine = Color(0xFFD8DEE8);
const _actionBlue = Color(0xFF2563EB);

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

class _MonthlyAnimatedActionButtonState extends State<MonthlyAnimatedActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.96,
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

  @override
  Widget build(BuildContext context) {
    final label = widget.buttonLabel ?? '정기 정산 생성';
    final enabled = widget.enabled && !widget.isLoading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FilledButton(
          onPressed: enabled ? _handleTap : null,
          style: FilledButton.styleFrom(
            backgroundColor: _actionInk,
            disabledBackgroundColor: const Color(0xFFEFF2F7),
            foregroundColor: Colors.white,
            disabledForegroundColor: const Color(0xFF98A2B3),
            elevation: 0,
            minimumSize: const Size.fromHeight(56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _actionLine),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: widget.isLoading
                ? const Row(
                    key: ValueKey('loading'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 10),
                      Text('처리 중...', style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  )
                : Row(
                    key: const ValueKey('idle'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.leadingIcon ?? Icons.check_circle_outline, size: 18, color: label.contains('결제') ? _actionBlue : Colors.white),
                      const SizedBox(width: 8),
                      Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
