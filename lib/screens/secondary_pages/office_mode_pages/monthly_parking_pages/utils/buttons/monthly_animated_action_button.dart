import 'package:flutter/material.dart';

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
  State<MonthlyAnimatedActionButton> createState() => _MonthlyAnimatedActionButtonState();
}

class _MonthlyAnimatedActionButtonState extends State<MonthlyAnimatedActionButton>
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
    final String label = widget.buttonLabel ?? '정기 정산 생성';

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: widget.isLoading ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo[50],
          foregroundColor: Colors.indigo[800],
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(
              color: Colors.indigo,
              width: 1.5,
            ),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: widget.isLoading
              ? const SizedBox(
            key: ValueKey('loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.black,
            ),
          )
              : Text(
            key: const ValueKey('buttonText'),
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
