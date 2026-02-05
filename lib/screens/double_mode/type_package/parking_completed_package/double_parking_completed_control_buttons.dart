import 'package:flutter/material.dart';

import '../double_departure_completed_bottom_sheet.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 상태 색상
class _Palette {
  static const base = Color(0xFF37474F); // primary
  static const dark = Color(0xFF37474F); // 강조 텍스트/아이콘

  // 상태 강조 색
  static const danger = Color(0xFFD32F2F); // ✅ 스마트 검색(붉은색)
  static const success = Color(0xFF2E7D32); // 출차 완료(초록색)
}

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
    final Color selectedItemColor = _Palette.base;
    final Color unselectedItemColor = _Palette.dark.withOpacity(.55);

    // ✅ 스마트 검색 색상: 붉은색으로 고정
    const Color smartSearchColor = _Palette.danger;

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
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
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: isStatusMode
                ? const Icon(Icons.analytics, key: ValueKey('status'))
                : const Icon(Icons.table_rows, key: ValueKey('table')),
          ),
          label: isStatusMode ? '현황 모드' : '테이블 모드',
        ),

        // 1) 스마트 검색 (✅ 텍스트 변경 + ✅ 아이콘/라벨 붉은색)
        const BottomNavigationBarItem(
          icon: Icon(Icons.search, color: smartSearchColor),
          label: '스마트 검색',
        ),

        // 2) 출차 완료
        const BottomNavigationBarItem(
          icon: Icon(Icons.directions_car, color: _Palette.success),
          label: '출차 완료',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 0:
            onToggleViewMode();
            break;
          case 1:
          // ✅ 기존 동작 유지
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
