import 'package:flutter/material.dart';
import '../../utils/app_colors.dart'; // 앱의 공통 색상 정의

/// BottomNavigation 위젯
/// - 하단 내비게이션 바의 UI를 구성하며, 키패드 또는 액션 버튼을 표시합니다.
/// - showKeypad: 키패드 표시 여부를 결정하는 플래그
/// - keypad: 키패드 위젯
/// - actionButton: 액션 버튼 위젯
/// - onTap: 내비게이션 바를 탭할 때 호출되는 콜백
class BottomNavigation extends StatelessWidget {
  // 키패드 표시 여부 플래그
  final bool showKeypad;

  // 표시할 키패드 위젯
  final Widget keypad;

  // 표시할 액션 버튼 위젯
  final Widget actionButton;

  // 탭 이벤트를 처리하는 콜백 (옵션)
  final VoidCallback? onTap;

  /// 생성자
  /// - 키패드와 액션 버튼을 필수 인자로 받으며, onTap은 선택적으로 설정 가능
  const BottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
  });

  /// 하단 내비게이션의 UI 빌드
  @override
  Widget build(BuildContext context) {
    // 현재 내비게이션의 배경색 정보를 디버그 출력
    print('BottomNavigation rendered with color: ${AppColors.bottomNavBackground}');
    return GestureDetector(
      // 사용자가 탭했을 때 실행될 콜백
      onTap: onTap ?? () {}, // onTap이 null일 경우 기본 빈 콜백 사용
      child: Container(
        // 컨테이너 스타일 정의
        decoration: const BoxDecoration(
          color: AppColors.bottomNavBackground, // 배경색 설정
        ),
        padding: const EdgeInsets.all(16.0), // 내부 패딩 설정
        child: _buildContent(), // 내용물 빌드
      ),
    );
  }

  /// 표시할 내용을 결정
  /// - showKeypad이 true면 키패드를, false면 액션 버튼을 표시
  Widget _buildContent() {
    return showKeypad ? keypad : actionButton;
  }
}
