// lib/screens/secondary_package/office_mode_package/monthly_management_package/monthly_bottom_navigation.dart
import 'package:flutter/material.dart';

import '../../../../../utils/app_colors.dart';

/// 서비스 로그인 카드(Deep Blue 팔레트)와 톤을 맞춘 보조 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const light = Color(0xFF5472D3);
}

/// 하단 고정 네비: 액션 버튼 vs. 숫자/한글 키패드 토글 표시
/// - 색상은 앱 테마(colorScheme) + 서비스 팔레트 기반으로 토널 처리
/// - 키패드 표시 시 살짝 진한 톤/상단 보더로 레이어를 구분
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

    // 기본 바탕(앱 공통) → showKeypad 시 서비스 팔레트로 약간 짙게
    final Color baseBg = backgroundColor ?? AppColors.bottomNavBackground;
    final Color effectiveBg =
        backgroundColor ?? (showKeypad ? _SvcColors.light.withOpacity(.12) : baseBg);

    final Color borderTop =
    showKeypad ? _SvcColors.base.withOpacity(.28) : cs.outlineVariant.withOpacity(.5);

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
              // 상단에 살짝 얹힌 느낌
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
