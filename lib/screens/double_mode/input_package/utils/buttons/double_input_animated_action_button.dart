import 'package:flutter/material.dart';

class DoubleInputAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;

  const DoubleInputAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
  });

  @override
  State<DoubleInputAnimatedActionButton> createState() => _DoubleInputAnimatedActionButtonState();
}

class _DoubleInputAnimatedActionButtonState extends State<DoubleInputAnimatedActionButton>
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
    final bool isLocationSelected = widget.isLocationSelected;

    const String label = '입차 완료';

    final bool isDisabled = isLoading || !isLocationSelected;

    final bg = isLocationSelected ? cs.primary : cs.surfaceContainerLow;
    final fg = isLocationSelected ? cs.onPrimary : cs.onSurfaceVariant;
    final border = isLocationSelected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.85);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: border, width: 1.5),
          ),
          disabledBackgroundColor: cs.surfaceContainerLow,
          disabledForegroundColor: cs.onSurfaceVariant,
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed) ? cs.primary.withOpacity(0.10) : null,
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
              valueColor: AlwaysStoppedAnimation<Color>(isLocationSelected ? cs.onPrimary : cs.onSurfaceVariant),
            ),
          )
              : const Text(
            key: ValueKey('buttonText'),
            label,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
