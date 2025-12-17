// lib/screens/secondary_package/office_mode_package/monthly_management_package/monthly_bottom_navigation.dart
import 'package:flutter/material.dart';

/// 하단 고정 네비: 액션 버튼 vs. 숫자/한글 키패드 토글 표시
/// - ✅ 바텀시트 배경색과 다르게 노는 문제를 방지하기 위해
///   기본 배경을 AppColors 같은 고정 흰색이 아니라 `Theme.colorScheme.surface`로 통일
/// - showKeypad일 때만 약간 톤 변화(원치 않으면 baseBg 그대로 사용하면 됨)
/// - Offstage + AnimatedOpacity로 상태 유지 + 자연스러운 페이드
class MonthlyBottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const MonthlyBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  static const _kDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 기본 배경을 바텀시트/테마 surface로 통일 (배경 이질감 방지)
    final Color baseBg = backgroundColor ?? cs.surface;

    // 키패드 표시 시에만 아주 약한 톤 구분
    final Color effectiveBg =
    showKeypad ? cs.surfaceVariant.withOpacity(.55) : baseBg;

    final Color borderTop =
    showKeypad ? cs.primary.withOpacity(.18) : cs.outlineVariant.withOpacity(.5);

    return GestureDetector(
      onTap: onTap ?? () {},
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: _kDuration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: effectiveBg,
            border: Border(top: BorderSide(color: borderTop, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        // 액션 버튼은 키패드가 보일 때 숨김 (상태 유지)
        AnimatedOpacity(
          duration: _kDuration,
          opacity: showKeypad ? 0.0 : 1.0,
          curve: Curves.easeOut,
          child: Offstage(
            offstage: showKeypad,
            child: actionButton,
          ),
        ),

        // 키패드는 항상 위젯 트리에 있고 표시 여부만 조절 (상태 유지)
        AnimatedOpacity(
          duration: _kDuration,
          opacity: showKeypad ? 1.0 : 0.0,
          curve: Curves.easeOut,
          child: Offstage(
            offstage: !showKeypad,
            child: keypad,
          ),
        ),
      ],
    );
  }
}
