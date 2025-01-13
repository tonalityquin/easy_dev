import 'package:flutter/material.dart';
import '../../utils/app_colors.dart'; // 앱의 공통 색상 정의

/// **SecondaryBottomNavigation 위젯**
/// - 하단 내비게이션 바 UI를 구성
/// - 키패드 또는 액션 버튼을 조건에 따라 표시
///
/// **매개변수**:
/// - [showKeypad]: 키패드 표시 여부를 결정하는 플래그
/// - [keypad]: 키패드로 표시할 위젯
/// - [actionButton]: 액션 버튼으로 표시할 위젯
/// - [onTap]: 내비게이션 바를 탭했을 때 실행되는 콜백 (선택적)
class SecondaryBottomNavigation extends StatelessWidget {
  /// **키패드 표시 여부 플래그**
  /// - `true`: 키패드를 표시
  /// - `false`: 액션 버튼을 표시
  final bool showKeypad;

  /// **키패드 위젯**
  /// - 키패드로 표시할 내용
  final Widget keypad;

  /// **액션 버튼 위젯**
  /// - 키패드가 아닌 경우 표시할 액션 버튼
  final Widget actionButton;

  /// **탭 이벤트 콜백** (선택적)
  /// - 내비게이션 바를 탭했을 때 실행
  final VoidCallback? onTap;

  /// **BottomNavigation 생성자**
  /// - [showKeypad]: 키패드 표시 여부 (필수)
  /// - [keypad]: 표시할 키패드 위젯 (필수)
  /// - [actionButton]: 표시할 액션 버튼 위젯 (필수)
  /// - [onTap]: 탭 이벤트 콜백 (선택적)
  const SecondaryBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
  });

  /// **하단 내비게이션 UI 구성**
  @override
  Widget build(BuildContext context) {
    // 현재 내비게이션의 배경색 정보를 디버그 출력
    print('SecondaryBottomNavigation rendered with color: ${AppColors.bottomNavBackground}');

    return GestureDetector(
      // 내비게이션 바 탭 이벤트 처리
      onTap: onTap ?? () {}, // onTap이 null이면 기본 빈 콜백 설정
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bottomNavBackground, // 배경색 설정
        ),
        padding: const EdgeInsets.all(16.0), // 내부 패딩 설정
        child: _buildContent(), // 키패드 또는 액션 버튼 표시
      ),
    );
  }

  /// **표시할 내용 결정**
  /// - [showKeypad]가 `true`면 키패드를, `false`면 액션 버튼을 표시
  Widget _buildContent() {
    return showKeypad ? keypad : actionButton;
  }
}
