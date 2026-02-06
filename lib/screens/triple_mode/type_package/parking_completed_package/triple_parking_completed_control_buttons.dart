import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/page/triple_page_state.dart';
import '../../../../states/user/user_state.dart';

import '../triple_departure_completed_bottom_sheet.dart';

/// ✅ 출차 요청(PlateType.departureRequests) 건수(aggregation count) 표시 위젯
/// - plates 컬렉션에서 (type == departure_requests && area == area && isSelected == false) 조건으로 count()
/// - refreshToken 변경 시(같은 area여도) 다시 count().get()
class DepartureRequestsAggregationCount extends StatefulWidget {
  final String area;
  final Color color;
  final double fontSize;

  /// ✅ 같은 area에서도 재조회 트리거로 사용
  final int refreshToken;

  const DepartureRequestsAggregationCount({
    super.key,
    required this.area,
    required this.color,
    this.fontSize = 18,
    required this.refreshToken,
  });

  @override
  State<DepartureRequestsAggregationCount> createState() =>
      _DepartureRequestsAggregationCountState();
}

class _DepartureRequestsAggregationCountState
    extends State<DepartureRequestsAggregationCount> {
  Future<int>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant DepartureRequestsAggregationCount oldWidget) {
    super.didUpdateWidget(oldWidget);

    final areaChanged = oldWidget.area.trim() != widget.area.trim();
    final tokenChanged = oldWidget.refreshToken != widget.refreshToken;

    if (areaChanged || tokenChanged) {
      _future = _fetch(); // ✅ 같은 area여도 token이 바뀌면 재조회
    }
  }

  Future<int> _fetch() async {
    final area = widget.area.trim();
    if (area.isEmpty) return 0;

    final agg = FirebaseFirestore.instance
        .collection('plates')
        .where(
      PlateFields.type,
      isEqualTo: PlateType.departureRequests.firestoreValue,
    )
        .where(PlateFields.area, isEqualTo: area)
        .where(PlateFields.isSelected, isEqualTo: false)
        .count();

    final snap = await agg.get();
    return snap.count ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area.trim();

    // area가 비어있으면 표시만 0으로(조회 시도 없음)
    if (area.isEmpty) {
      return Center(
        child: Text(
          '0',
          style: TextStyle(
            color: widget.color,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return FutureBuilder<int>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              // ✅ valueColor 유지 (기존 동작/색 유지)
              valueColor: AlwaysStoppedAnimation<Color>(widget.color),
            ),
          );
        }

        if (snap.hasError) {
          return Center(
            child: Text(
              '—',
              style: TextStyle(
                color: widget.color,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        final count = snap.data ?? 0;
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$count',
            style: TextStyle(
              color: widget.color,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}

/// ✅ Triple 입차완료 컨트롤바(현재 UX 기준 “현황 ↔ 테이블” + “검색(요청 플로우 시작)” + “출차완료”만 유지)
///
/// - TripleParkingCompletedPage가 status/locationPicker 2모드만 제공하므로
///   레거시 분기(사전정산/상태수정/삭제/정렬/Firestore write)는 도달 불가 → 삭제
class TripleParkingCompletedControlButtons extends StatelessWidget {
  /// true: 현황 모드 / false: 테이블 모드
  final bool isStatusMode;

  /// 0번 버튼: 현황 ↔ 테이블 토글
  final VoidCallback onToggleViewMode;

  /// 1번 버튼: (기존) 출차 요청 플로우 시작(현재 구현은 검색 다이얼로그 오픈)
  final VoidCallback showSearchDialog;

  const TripleParkingCompletedControlButtons({
    super.key,
    required this.isStatusMode,
    required this.onToggleViewMode,
    required this.showSearchDialog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ✅ area 변경에 따라 count가 재조회되도록 select로 구독
    final userArea =
    context.select<UserState, String>((s) => s.currentArea).trim();
    final stateArea =
    context.select<AreaState, String>((s) => s.currentArea).trim();
    final departureCountArea = userArea.isNotEmpty ? userArea : stateArea;

    // ✅ 브랜드 테마 기반 컬러 (독립 프리셋 포함)
    final Color navBg = cs.surface; // ❌ Colors.white 제거
    final Color selectedItemColor = cs.primary;
    final Color unselectedItemColor = cs.onSurfaceVariant.withOpacity(.65);

    // ✅ 상태 색상
    // - “출차 요청(붉은색)” 의미: ColorScheme.error 사용(테마/독립프리셋 연동)
    final Color dangerColor = cs.error;

    // - “출차 완료(성공)”은 ColorScheme에 success가 없으므로 tertiary로 매핑(테마 연동)
    final Color successColor = cs.tertiary;

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
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: isStatusMode
                ? const Icon(Icons.analytics, key: ValueKey('status'))
                : const Icon(Icons.table_rows, key: ValueKey('table')),
          ),
          label: isStatusMode ? '현황 모드' : '테이블 모드',
        ),

        // 1) (아이콘/카운트/동작 유지) ✅ 텍스트만 변경
        BottomNavigationBarItem(
          icon: Selector<TriplePageState, int>(
            selector: (_, s) => s.departureRequestsCountRefreshToken,
            builder: (context, token, _) {
              return DepartureRequestsAggregationCount(
                area: departureCountArea,
                color: dangerColor, // ✅ _Palette.danger → cs.error
                fontSize: 18,
                refreshToken: token,
              );
            },
          ),
          label: '스마트 검색',
        ),

        // 2) 출차 완료
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_car, color: successColor),
          label: '출차 완료',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 0:
            onToggleViewMode();
            break;
          case 1:
          // ✅ 기존 동작 유지: 출차 요청 플로우 시작(검색 다이얼로그)
            showSearchDialog();
            break;
          case 2:
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const TripleDepartureCompletedBottomSheet(),
            );
            break;
        }
      },
    );
  }
}
