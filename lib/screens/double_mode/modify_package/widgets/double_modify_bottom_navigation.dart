import 'package:flutter/material.dart';
import '../../../../utils/init/app_colors.dart';

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
    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.bottomNavBackground,
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
