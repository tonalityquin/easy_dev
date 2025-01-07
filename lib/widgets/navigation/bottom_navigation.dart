import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';

class BottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;

  const BottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    print('BottomNavigation rendered with color: ${AppColors.bottomNavBackground}');
    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bottomNavBackground,
        ),
        padding: const EdgeInsets.all(16.0),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return showKeypad ? keypad : actionButton;
  }
}
