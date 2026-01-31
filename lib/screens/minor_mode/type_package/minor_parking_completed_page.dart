import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/minor_plate_state.dart';
import '../../../states/user/user_state.dart';

import '../../../widgets/navigation/minor_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/minor_parking_completed_search_bottom_sheet.dart';

import 'parking_completed_package/minor_parking_completed_real_time_table.dart';
import 'parking_completed_package/minor_parking_status_page.dart';

/// ✅ Minor 입차완료 페이지는 "현황(status) ↔ 실시간 테이블(locationPicker)" 2가지 화면만 제공합니다.
/// - 과거 레거시였던 plateList/정렬/구역필터/PlateContainer 리스트 UI는 현재 흐름에서 사용되지 않아 제거됨.
enum MinorParkingViewMode { status, locationPicker }

class MinorParkingCompletedPage extends StatefulWidget {
  const MinorParkingCompletedPage({super.key});

  /// ✅ 상위(MinorTypePage)에서 하단 컨트롤바가 현재 모드를 알 수 있도록 노출
  static final ValueNotifier<MinorParkingViewMode> modeNotifier =
  ValueNotifier<MinorParkingViewMode>(MinorParkingViewMode.status);

  static void reset(GlobalKey key) {
    (key.currentState as _MinorParkingCompletedPageState?)?._resetInternalState();
  }

  /// ✅ 외부(상위 Scaffold)에서 '현황 ↔ 테이블' 토글 제어
  static void toggleViewMode(GlobalKey key) {
    (key.currentState as _MinorParkingCompletedPageState?)?._toggleViewMode();
  }

  /// ✅ 외부에서 검색 다이얼로그 오픈
  static void openSearchDialog(GlobalKey key, BuildContext context) {
    (key.currentState as _MinorParkingCompletedPageState?)?._showSearchDialog(context);
  }

  @override
  State<MinorParkingCompletedPage> createState() => _MinorParkingCompletedPageState();
}

class _MinorParkingCompletedPageState extends State<MinorParkingCompletedPage> {
  MinorParkingViewMode _mode = MinorParkingViewMode.status;

  // ✅ Status 페이지 강제 재생성용 키 시드 (홈 버튼 리셋 시 증가)
  int _statusKeySeed = 0;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  void _syncModeNotifier() {
    MinorParkingCompletedPage.modeNotifier.value = _mode;
  }

  @override
  void initState() {
    super.initState();
    _syncModeNotifier();
  }

  void _resetInternalState() {
    setState(() {
      _mode = MinorParkingViewMode.status;
      _statusKeySeed++; // ✅ Status 재생성 트리거 → StatusPage 집계 재실행
    });
    _syncModeNotifier();
    _log('reset page state');
  }

  void _toggleViewMode() {
    setState(() {
      _mode = (_mode == MinorParkingViewMode.status)
          ? MinorParkingViewMode.locationPicker
          : MinorParkingViewMode.status;
    });
    _syncModeNotifier();

    _log(_mode == MinorParkingViewMode.status ? 'mode → status' : 'mode → locationPicker(table)');
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;
    _log('open search dialog');

    showDialog(
      context: context,
      builder: (_) {
        return MinorParkingCompletedSearchBottomSheet(
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
      onWillPop: () async {
        final plateState = context.read<MinorPlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate =
        plateState.minorGetSelectedPlate(PlateType.parkingCompleted, userName);

        // ✅ 선택된 차량이 있으면 "뒤로가기 = 선택 해제" 우선
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.minorTogglePlateIsSelected(
            collection: PlateType.parkingCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          _log('clear selection');
          return false;
        }

        // ✅ 테이블 → 현황으로 한 단계 되돌기
        if (_mode == MinorParkingViewMode.locationPicker) {
          setState(() => _mode = MinorParkingViewMode.status);
          _syncModeNotifier();
          _log('back → status');
          return false;
        }

        // 최상위(status)면 pop 허용
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const MinorTopNavigation(),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
          ),
        ),

        // ✅ 변경 핵심:
        // 기존 bottomNavigationBar(MinorParkingCompletedControlButtons) 제거
        // → 그 높이만큼 body 영역 확장
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case MinorParkingViewMode.status:
        return MinorParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case MinorParkingViewMode.locationPicker:
      // ✅ 리팩터링: 레거시 “주차 구역 리스트/plateList” 대신
      //    Minor 모드 전용 “실시간(view) 테이블(입차 완료 / 출차 요청)” 임베드 출력
        return MinorParkingCompletedRealTimeTable();
    }
  }
}
