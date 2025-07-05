import 'package:flutter/material.dart';

import '../../../utils/app_colors.dart';

class InputBottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const InputBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
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
    return Stack(
      children: [
        // 액션 버튼은 키패드가 보일 때 숨김
        Offstage(
          offstage: showKeypad,
          child: actionButton,
        ),
        // 키패드는 항상 위젯 트리에 있고 표시 여부만 조절
        Offstage(
          offstage: !showKeypad,
          child: keypad,
        ),
      ],
    );
  }
}
