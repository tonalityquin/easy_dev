import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/triple_plate_state.dart';
import '../../../states/user/user_state.dart';

import '../../../widgets/navigation/triple_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/triple_parking_completed_search_bottom_sheet.dart';

import 'parking_completed_package/triple_parking_completed_real_time_table.dart';
import 'parking_completed_package/triple_parking_status_page.dart';

/// ✅ 이 페이지는 "현황(status) ↔ 실시간 테이블(locationPicker)" 2가지 화면만 제공합니다.
/// - 과거 레거시였던 plateList/정렬/구역필터 UI는 현재 흐름에서 사용되지 않아 제거됨.
enum TripleParkingViewMode { status, locationPicker }

class TripleParkingCompletedPage extends StatefulWidget {
  const TripleParkingCompletedPage({super.key});

  /// ✅ 상위(TripleTypePage)에서 하단 컨트롤바가 현재 모드를 알 수 있도록 노출
  static final ValueNotifier<TripleParkingViewMode> modeNotifier =
  ValueNotifier<TripleParkingViewMode>(TripleParkingViewMode.status);

  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _TripleParkingCompletedPageState?)?._resetInternalState();
  }

  /// ✅ 외부(상위 Scaffold)에서 '현황 ↔ 테이블' 토글 제어
  static void toggleViewMode(GlobalKey key) {
    (key.currentState as _TripleParkingCompletedPageState?)?._toggleViewMode();
  }

  /// ✅ 외부에서 검색 다이얼로그 오픈
  static void openSearchDialog(GlobalKey key, BuildContext context) {
    (key.currentState as _TripleParkingCompletedPageState?)?._showSearchDialog(context);
  }

  @override
  State<TripleParkingCompletedPage> createState() => _TripleParkingCompletedPageState();
}

class _TripleParkingCompletedPageState extends State<TripleParkingCompletedPage> {
  TripleParkingViewMode _mode = TripleParkingViewMode.status; // 기본은 현황 화면

  // ✅ Status 페이지 강제 재생성용 키 시드 (홈 버튼 리셋 시 증가)
  int _statusKeySeed = 0;

  // ─────────────────────────────────────────────────────────────
  // 로컬 로그(디버그 전용)
  // ─────────────────────────────────────────────────────────────
  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  void _syncModeNotifier() {
    TripleParkingCompletedPage.modeNotifier.value = _mode;
  }

  @override
  void initState() {
    super.initState();
    _syncModeNotifier();
  }

  /// 홈 재탭/진입 시 초기 상태로 되돌림
  /// - 홈 기본은 현황 모드(status).
  void _resetInternalState() {
    setState(() {
      _mode = TripleParkingViewMode.status;
      _statusKeySeed++; // ✅ Status 재생성 트리거 → ParkingStatusPage 집계 재실행
    });
    _syncModeNotifier();
    _log('reset page state');
  }

  /// ✅ 현황 모드 ↔ 테이블 모드 토글
  /// - 현황 모드: TripleParkingStatusPage
  /// - 테이블 모드: 실시간(view) 테이블(입차완료/출차요청)
  void _toggleViewMode() {
    setState(() {
      _mode = (_mode == TripleParkingViewMode.status)
          ? TripleParkingViewMode.locationPicker
          : TripleParkingViewMode.status;
    });
    _syncModeNotifier();

    _log(_mode == TripleParkingViewMode.status
        ? 'mode → status'
        : 'mode → locationPicker(table)');
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;
    _log('open search dialog');

    showDialog(
      context: context,
      builder: (context) {
        return TripleParkingCompletedSearchBottomSheet(
          // ✅ 이 바텀시트는 내부에서 검색/선택 흐름을 완결하므로,
          //    여기서는 콜백을 비워두어도 됩니다(시그니처 유지).
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      // 시스템/뒤로가기 처리:
      // 1) 선택된 번호판이 있으면 선택 해제
      // 2) 테이블 모드면 현황 모드로 후퇴
      // 3) 현황 모드면 pop 허용
      onWillPop: () async {
        final plateState = context.read<TriplePlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate =
        plateState.tripleGetSelectedPlate(PlateType.parkingCompleted, userName);

        // 1) 선택된 번호판이 있으면 선택 해제 먼저
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.tripleTogglePlateIsSelected(
            collection: PlateType.parkingCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          _log('clear selection');
          return false;
        }

        // 2) 테이블 → 현황으로 한 단계 되돌기
        if (_mode == TripleParkingViewMode.locationPicker) {
          setState(() => _mode = TripleParkingViewMode.status);
          _syncModeNotifier();
          _log('back → status');
          return false;
        }

        // 3) 최상위(status)면 pop 허용
        return true;
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const TripleTopNavigation(),
          centerTitle: true,

          // ✅ 브랜드(ColorScheme) 기반
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withOpacity(0.85),
              width: 1,
            ),
          ),
        ),

        // ✅ 변경 핵심:
        // 이 페이지의 bottomNavigationBar는 제거되어 있고,
        // 하단 컨트롤바는 상위(TripleTypePage)에서 렌더링합니다.
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case TripleParkingViewMode.status:
      // ✅ 리셋마다 키가 바뀌어 ParkingStatusPage의 State가 새로 만들어짐 → 집계 재실행
        return TripleParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case TripleParkingViewMode.locationPicker:
      // ✅ 리팩터링: 기존 “주차 구역 리스트” 대신
      //    트리플 모드 전용 “실시간(view) 테이블(입차 완료 / 출차 요청)” 임베드 출력
        return const TripleParkingCompletedRealTimeTable();
    }
  }
}
