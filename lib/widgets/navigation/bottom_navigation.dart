import 'package:flutter/material.dart';
import '../../utils/app_colors.dart'; // 앱의 공통 색상 정의

/// **BottomNavigation**
/// - 화면 하단에 표시되는 네비게이션 위젯
/// - 키패드와 동작 버튼을 조건에 따라 표시
/// - 배경색 커스터마이징 가능
class BottomNavigation extends StatelessWidget {
  final bool showKeypad; // 키패드 표시 여부
  final Widget keypad; // 키패드 위젯
  final Widget actionButton; // 동작 버튼 위젯
  final VoidCallback? onTap; // 탭 이벤트 콜백 (옵션)
  final Color? backgroundColor; // 배경색 (옵션)

  const BottomNavigation({
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
      onTap: onTap ?? () {}, // 탭 이벤트 처리 (기본값은 빈 동작)
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.bottomNavBackground, // 배경색 설정
        ),
        padding: const EdgeInsets.all(16.0), // 내부 여백 설정
        child: _buildContent(), // 콘텐츠 빌드
      ),
    );
  }

  /// **_buildContent**
  /// - `showKeypad` 상태에 따라 키패드 또는 동작 버튼 반환
  Widget _buildContent() {
    return showKeypad ? keypad : actionButton;
  }
}
