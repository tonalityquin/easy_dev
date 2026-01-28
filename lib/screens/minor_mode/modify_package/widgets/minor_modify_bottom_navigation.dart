import 'package:flutter/material.dart';
import '../../../../utils/init/app_colors.dart';

class MinorModifyBottomNavigation extends StatelessWidget {
  /// 기존 호환: keypad 모드가 필요 없는 화면에서는 null로 둬도 됨
  final bool? showKeypad;
  final Widget? keypad;

  /// 기본 액션 영역(버튼들)
  final Widget actionButton;

  /// 바텀 영역 탭 처리(키패드 닫기 등). 없으면 탭 무시.
  final VoidCallback? onTap;

  /// 배경색 오버라이드(기본은 AppColors.bottomNavBackground 유지)
  final Color? backgroundColor;

  const MinorModifyBottomNavigation({
    super.key,
    this.showKeypad,
    this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  bool get _shouldShowKeypad => (showKeypad == true) && keypad != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg = backgroundColor ??
        // ✅ 기존 AppColors를 우선 유지하되, 테마 대비가 깨질 경우를 고려해 surface로 폴백 가능
        AppColors.bottomNavBackground;

    // ✅ GestureDetector 대신 InkWell을 쓰면 ripple이 생기지만
    //    기존 UX(무음 탭)를 유지하기 위해 GestureDetector 유지.
    // ✅ 다만 "onTap ?? () {}" 패턴은 불필요한 탭 이벤트를 항상 소비하므로 제거.
    return Semantics(
      container: true,
      label: 'minor_modify_bottom_navigation',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // ✅ 빈 영역도 탭 인식
        onTap: onTap, // ✅ null이면 탭 자체를 소비하지 않음
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withOpacity(0.55),
                width: 1,
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            // ✅ 시스템 하단 영역을 고려해 안전 패딩 반영(겹침 방지)
            16 + MediaQuery.of(context).padding.bottom,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<bool>(_shouldShowKeypad),
              child: _shouldShowKeypad ? keypad! : actionButton,
            ),
          ),
        ),
      ),
    );
  }
}
