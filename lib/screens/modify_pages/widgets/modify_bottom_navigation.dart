import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';

class ModifyBottomNavigation extends StatelessWidget {
  final bool? showKeypad; // ✅ 선택적
  final Widget? keypad; // ✅ 선택적
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const ModifyBottomNavigation({
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
