import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/page/minor_page_state.dart';
import '../../../../states/user/user_state.dart';

import '../minor_departure_completed_bottom_sheet.dart';

/// ✅ 입차 요청(PlateType.parkingRequests) 건수(aggregation count) 표시 위젯
/// - plates 컬렉션에서 (type == parking_requests && area == area && isSelected == false) 조건으로 count()
/// - refreshToken 변경 시(같은 area여도) 다시 count().get()
class ParkingRequestsAggregationCount extends StatefulWidget {
  final String area;
  final Color color;
  final double fontSize;

  /// ✅ 같은 area에서도 재조회 트리거로 사용
  final int refreshToken;

  const ParkingRequestsAggregationCount({
    super.key,
    required this.area,
    required this.color,
    this.fontSize = 18,
    required this.refreshToken,
  });

  @override
  State<ParkingRequestsAggregationCount> createState() =>
      _ParkingRequestsAggregationCountState();
}

class _ParkingRequestsAggregationCountState
    extends State<ParkingRequestsAggregationCount> {
  Future<int>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant ParkingRequestsAggregationCount oldWidget) {
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
      isEqualTo: PlateType.parkingRequests.firestoreValue,
    )
        .where(PlateFields.area, isEqualTo: area)
        .where(PlateFields.isSelected, isEqualTo: false) // ✅ 주행(선점) 중 제외
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

/// ✅ (기존) 출차 요청(PlateType.departureRequests) 건수(aggregation count) 표시 위젯
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

/// ✅ Minor 입차완료 컨트롤바(현재 UX 기준 reachable 로직만 유지)
///
/// 유지 기능:
/// 0) (아이콘) 입차 요청 count 표시 + 탭하면 현황↔테이블 토글
/// 1) (아이콘) (기존: 출차 요청 count) 표시 + 탭하면 검색 다이얼로그
/// 2) 출차 완료 바텀시트
///
/// ✅ 변경점:
/// - 하드코딩 팔레트/배경 제거 → Theme.of(context).colorScheme 기반
/// - 독립 프리셋(KB 등)에서도 surface/primary가 반영되도록 구성
/// - "스마트 검색" 텍스트 유지
class MinorParkingCompletedControlButtons extends StatelessWidget {
  /// true: 현황 모드 / false: 테이블 모드
  final bool isStatusMode;

  /// 0번 버튼 탭: 현황 ↔ 테이블
  final VoidCallback onToggleViewMode;

  /// 1번 버튼 탭: 검색 다이얼로그(기존 동작 유지)
  final VoidCallback showSearchDialog;

  const MinorParkingCompletedControlButtons({
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
    final countArea = userArea.isNotEmpty ? userArea : stateArea;

    // ✅ 브랜드 테마 기반(독립 프리셋 포함)
    final Color navBg = cs.surface; // ❌ Colors.white 제거
    final Color selectedItemColor = cs.primary;
    final Color unselectedItemColor = cs.onSurfaceVariant.withOpacity(.65);

    // ✅ 상태 색상(테마 연동)
    // - 출차요청 강조(기존 빨강): error 사용
    final Color dangerColor = cs.error;

    // - 출차완료(성공/초록): ColorScheme에 success가 없으므로 tertiary 매핑(테마 연동)
    final Color successColor = cs.tertiary;

    // - 입차요청 강조(기존 파랑): secondary 또는 primaryContainer 중 택1
    //   여기서는 "primary와 충돌 방지"를 위해 secondary 권장.
    final Color entryRequestColor = cs.secondary;

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
        // 0) (아이콘) 입차 요청 count / (탭) 모드 토글
        BottomNavigationBarItem(
          icon: Selector<MinorPageState, int>(
            // 기존 코드와 호환: 동일 refreshToken으로 재조회 트리거
            selector: (_, s) => s.departureRequestsCountRefreshToken,
            builder: (context, token, _) {
              return ParkingRequestsAggregationCount(
                area: countArea,
                color: entryRequestColor,
                fontSize: 18,
                refreshToken: token,
              );
            },
          ),
          label: isStatusMode ? '현황 모드' : '테이블 모드',
        ),

        // 1) 출차 요청 count / (탭) 검색 다이얼로그
        BottomNavigationBarItem(
          icon: Selector<MinorPageState, int>(
            selector: (_, s) => s.departureRequestsCountRefreshToken,
            builder: (context, token, _) {
              return DepartureRequestsAggregationCount(
                area: countArea,
                color: dangerColor,
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
          // ✅ 기능은 그대로 유지(검색 다이얼로그)
            showSearchDialog();
            break;
          case 2:
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const MinorDepartureCompletedBottomSheet(),
            );
            break;
        }
      },
    );
  }
}
