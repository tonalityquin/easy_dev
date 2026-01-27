import 'package:flutter/material.dart';

class DoubleInputBottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const DoubleInputBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        Offstage(
          offstage: showKeypad,
          child: actionButton,
        ),
        Offstage(
          offstage: !showKeypad,
          child: keypad,
        ),
      ],
    );
  }
}
