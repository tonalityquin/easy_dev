import 'package:flutter/material.dart';

class DoubleModifyBottomNavigation extends StatelessWidget {
  final bool? showKeypad;
  final Widget? keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const DoubleModifyBottomNavigation({
    super.key,
    this.showKeypad,
    this.keypad,
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
          // ✅ AppColors.bottomNavBackground 제거 → 테마 기반
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
    if (showKeypad == true && keypad != null) {
      return keypad!;
    } else {
      return actionButton;
    }
  }
}
