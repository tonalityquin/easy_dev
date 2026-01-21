import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/double_plate_state.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

// import '../../utils/usage_reporter.dart';

import '../../../widgets/navigation/double_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/double_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'parking_completed_package/double_parking_completed_control_buttons.dart';
import 'parking_completed_package/double_parking_completed_location_picker.dart';
import 'parking_completed_package/double_parking_status_page.dart';

enum DoubleParkingViewMode { status, locationPicker, plateList }

class DoubleParkingCompletedPage extends StatefulWidget {
  const DoubleParkingCompletedPage({super.key});

  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _DoubleParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<DoubleParkingCompletedPage> createState() => _DoubleParkingCompletedPageState();
}

class _DoubleParkingCompletedPageState extends State<DoubleParkingCompletedPage> {
  DoubleParkingViewMode _mode = DoubleParkingViewMode.status; // 기본은 현황 화면
  String? _selectedParkingArea; // 선택된 주차 구역(location) (plateList 보존용)
  bool _isSorted = true; // true=최신순

  // ✅ Status 페이지 강제 재생성용 키 시드 (홈 버튼 리셋 시 증가)
  int _statusKeySeed = 0;

  // ─────────────────────────────────────────────────────────────
  // 로컬 로그(디버그 전용)
  // ─────────────────────────────────────────────────────────────
  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  /// 홈 재탭/진입 시 초기 상태로 되돌림
  /// ✅ 변경: 잠금 상태 제거. 홈 기본은 현황 모드(status).
  void _resetInternalState() {
    setState(() {
      _mode = DoubleParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _statusKeySeed++; // ✅ Status 재생성 트리거 → ParkingStatusPage 집계 재실행
    });
    _log('reset page state');
  }

  /// ✅ 현황 모드 ↔ 테이블 모드 토글
  /// - 현황 모드: DoubleParkingStatusPage
  /// - 테이블 모드: (리팩터링) DoubleParkingCompletedLocationPicker = 입차 완료(view) 테이블(임베드)
  void _toggleViewMode() {
    if (_mode == DoubleParkingViewMode.plateList) return; // 안전장치

    setState(() {
      _mode = (_mode == DoubleParkingViewMode.status)
          ? DoubleParkingViewMode.locationPicker
          : DoubleParkingViewMode.status;
    });

    _log(_mode == DoubleParkingViewMode.status ? 'mode → status' : 'mode → locationPicker(table)');
  }

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
    _log(_isSorted ? 'sort → 최신순' : 'sort → 오래된순');
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;
    _log('open search dialog');
    showDialog(
      context: context,
      builder: (context) {
        return DoubleParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  // ✅ 출차 요청 핸들러 (더블 모드에서는 사용하지 않음/호환용 스텁)
  void _doubleHandleDepartureRequested(BuildContext context) {
    // 더블 모드 요구사항: 출차 요청 없음
    _log('stub: departure request (double mode has no departure request)');
    showFailedSnackbar(context, "더블 모드에서는 출차 요청 기능이 없습니다.");
  }

  // ✅ (빌드 에러 방지) 컨트롤 버튼에서 요구하는 입차 요청 콜백 스텁(기존 시그니처 유지)
  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    // 더블 모드 요구사항: 입차 요청 없음
    _log('stub: entry parking request $plateNumber ($area)');
    showFailedSnackbar(context, "더블 모드에서는 입차 요청 기능이 없습니다.");
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 시스템/뒤로가기 처리: 선택/모드 단계적으로 해제
      onWillPop: () async {
        final plateState = context.read<DoublePlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.doubleGetSelectedPlate(PlateType.parkingCompleted, userName);

        // 선택된 번호판이 있으면 선택 해제 먼저
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.doubleTogglePlateIsSelected(
            collection: PlateType.parkingCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          _log('clear selection');
          return false;
        }

        // plateList → locationPicker → status 순으로 한 단계씩 되돌기
        if (_mode == DoubleParkingViewMode.plateList) {
          setState(() => _mode = DoubleParkingViewMode.locationPicker);
          _log('back → locationPicker');
          return false;
        } else if (_mode == DoubleParkingViewMode.locationPicker) {
          setState(() => _mode = DoubleParkingViewMode.status);
          _log('back → status');
          return false;
        }

        // 최상위(status)면 pop 허용
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const DoubleTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildBody(context),

        // ✅ 요구사항 유지: ControlButtons는 계속 보이게 유지
        bottomNavigationBar: DoubleParkingCompletedControlButtons(
          isParkingAreaMode: _mode == DoubleParkingViewMode.plateList,
          isStatusMode: _mode == DoubleParkingViewMode.status,
          isLocationPickerMode: _mode == DoubleParkingViewMode.locationPicker,
          isSorted: _isSorted,
          onToggleViewMode: _toggleViewMode,
          showSearchDialog: () => _showSearchDialog(context),
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest, // ✅ 더블: 스텁
          handleDepartureRequested: _doubleHandleDepartureRequested, // ✅ 더블: 스텁
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final plateState = context.watch<DoublePlateState>();
    final userName = context.read<UserState>().name;

    switch (_mode) {
      case DoubleParkingViewMode.status:
      // ✅ 리셋마다 키가 바뀌어 ParkingStatusPage의 State가 새로 만들어짐 → 집계 재실행
        return DoubleParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case DoubleParkingViewMode.locationPicker:
      // ✅ 리팩터링:
      // - 기존 “주차 구역 선택 리스트” 제거
      // - 더블 모드 요구사항(입차요청/출차요청 없음)에 따라
      //   “입차 완료(view) 테이블”만 body에 임베드 출력
        return DoubleParkingCompletedLocationPicker(
          onClose: () {
            if (!mounted) return;
            setState(() => _mode = DoubleParkingViewMode.status);
          },
        );

      case DoubleParkingViewMode.plateList:
      // 🔹 기존 plateList 화면은 보존(다른 경로에서 필요할 수 있음). 현재 기본 흐름에선 사용 안 함.
        List<PlateModel> plates = plateState.doubleGetPlatesByCollection(PlateType.parkingCompleted);
        if (_selectedParkingArea != null) {
          plates = plates.where((p) => p.location == _selectedParkingArea).toList();
        }
        plates.sort(
              (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime),
        );

        return ListView(
          padding: const EdgeInsets.all(8.0),
          children: [
            PlateContainer(
              data: plates,
              collection: PlateType.parkingCompleted,
              filterCondition: (request) => request.type == PlateType.parkingCompleted.firestoreValue,
              onPlateTap: (plateNumber, area) {
                context.read<DoublePlateState>().doubleTogglePlateIsSelected(
                  collection: PlateType.parkingCompleted,
                  plateNumber: plateNumber,
                  userName: userName,
                  onError: (msg) => showFailedSnackbar(context, msg),
                );
                _log('tap plate: $plateNumber');
              },
            ),
          ],
        );
    }
  }
}
