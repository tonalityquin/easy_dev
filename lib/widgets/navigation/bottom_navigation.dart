import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';

/// BottomNavigation : 키패드 및 액션 버튼 처리
class BottomNavigation extends StatelessWidget {
  final bool showKeypad; // 키패드 표시 여부
  final Widget keypad; // 키패드 위젯
  final Widget actionButton; // 액션 버튼 위젯
  final VoidCallback? onTap; // 클릭 이벤트 처리

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
      onTap: onTap ?? () {}, // 클릭 이벤트 처리
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bottomNavBackground, // 배경색
        ),
        padding: const EdgeInsets.all(16.0),
        child: showKeypad ? keypad : actionButton, // 상태에 따른 렌더링
      ),
    );
  }
}
