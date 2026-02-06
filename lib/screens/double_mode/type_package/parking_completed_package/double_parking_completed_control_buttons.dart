import 'package:flutter/material.dart';

import '../double_departure_completed_bottom_sheet.dart';

/// 더블 입차완료 화면 전용 컨트롤 바.
///
/// ✅ 현재 UX에서 사용되는 기능만 유지:
/// 0) 현황 ↔ 테이블 모드 토글
/// 1) 스마트 검색 다이얼로그
/// 2) 출차 완료 바텀시트
class DoubleParkingCompletedControlButtons extends StatelessWidget {
  /// true: 현황 모드 / false: 테이블 모드
  final bool isStatusMode;

  /// 0번 버튼: 현황 ↔ 테이블 토글
  final VoidCallback onToggleViewMode;

  /// 1번 버튼: 스마트 검색 다이얼로그 오픈
  final VoidCallback showSearchDialog;

  const DoubleParkingCompletedControlButtons({
    super.key,
    required this.isStatusMode,
    required this.onToggleViewMode,
    required this.showSearchDialog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ✅ 브랜드 테마 기반 토큰
    // - 독립 프리셋(KB 등)일 때도 cs.surface/cs.onSurface가 프리셋에 맞게 변하므로 배경 하얀 문제 방지
    final Color navBg = cs.surface;
    final Color selectedItemColor = cs.primary; // ✅ 하이라이트(독립 프리셋 highlightText)
    final Color unselectedItemColor = cs.onSurfaceVariant.withOpacity(.65);

    // ✅ 상태 색상
    // - “스마트 검색은 붉은색 고정” 요구를 유지하면서도,
    //   가능한 한 ColorScheme.error를 사용(테마와 동기화)
    final Color smartSearchColor = cs.error;

    // ✅ 성공(출차 완료) 색: ColorScheme에 별도 success가 없으므로
    // - 기본은 tertiary 사용(테마 연동)
    // - 만약 프로젝트에 성공색 토큰이 있다면 그쪽으로 교체 추천
    final Color departureCompletedColor = cs.tertiary;

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: navBg,
      elevation: 0,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      iconSize: 24,
      selectedItemColor: selectedItemColor,
      unselectedItemColor: unselectedItemColor,
      items: [
        // 0) 현황 ↔ 테이블
        BottomNavigationBarItem(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: isStatusMode
                ? const Icon(Icons.analytics, key: ValueKey('status'))
                : const Icon(Icons.table_rows, key: ValueKey('table')),
          ),
          label: isStatusMode ? '현황 모드' : '테이블 모드',
        ),

        // 1) 스마트 검색 (붉은색 고정: cs.error)
        BottomNavigationBarItem(
          icon: Icon(Icons.search, color: smartSearchColor),
          label: '스마트 검색',
        ),

        // 2) 출차 완료 (테마 연동: cs.tertiary)
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_car, color: departureCompletedColor),
          label: '출차 완료',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 0:
            onToggleViewMode();
            break;
          case 1:
            showSearchDialog();
            break;
          case 2:
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const DoubleDepartureCompletedBottomSheet(),
            );
            break;
        }
      },
    );
  }
}
