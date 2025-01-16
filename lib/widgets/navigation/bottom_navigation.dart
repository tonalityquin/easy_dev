import 'package:flutter/material.dart';
import '../../utils/app_colors.dart'; // 앱의 공통 색상 정의

class BottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const BottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor, // 배경색 커스터마이징 옵션 추가
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
    return showKeypad ? keypad : actionButton;
  }
}
