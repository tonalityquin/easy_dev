import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/minor_plate_state.dart';
import '../../../states/plate/movement_plate.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

import '../../../widgets/navigation/minor_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/minor_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'parking_completed_package/minor_parking_completed_control_buttons.dart';
import 'parking_completed_package/minor_parking_completed_real_time_table.dart';
import 'parking_completed_package/minor_parking_status_page.dart';

enum MinorParkingViewMode { status, locationPicker, plateList }

class MinorParkingCompletedPage extends StatefulWidget {
  const MinorParkingCompletedPage({super.key});

  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _MinorParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<MinorParkingCompletedPage> createState() => _MinorParkingCompletedPageState();
}

class _MinorParkingCompletedPageState extends State<MinorParkingCompletedPage> {
  MinorParkingViewMode _mode = MinorParkingViewMode.status; // 기본은 현황 화면
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
  void _resetInternalState() {
    setState(() {
      _mode = MinorParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _statusKeySeed++; // ✅ Status 재생성 트리거 → ParkingStatusPage 집계 재실행
    });
    _log('reset page state');
  }

  /// ✅ 현황 모드 ↔ 테이블 모드 토글
  /// - 현황 모드: MinorParkingStatusPage
  /// - 테이블 모드: (리팩터링) MinorParkingCompletedLocationPicker = 실시간(view) 테이블 3탭
  void _toggleViewMode() {
    if (_mode == MinorParkingViewMode.plateList) return; // 안전장치

    setState(() {
      _mode = (_mode == MinorParkingViewMode.status)
          ? MinorParkingViewMode.locationPicker
          : MinorParkingViewMode.status;
    });

    _log(_mode == MinorParkingViewMode.status ? 'mode → status' : 'mode → locationPicker(table)');
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
        return MinorParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  // ✅ 출차 요청 핸들러 (기존 로직 유지)
  void _minorHandleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>();
    final userName = context.read<UserState>().name;
    final plateState = context.read<MinorPlateState>();
    final selectedPlate = plateState.minorGetSelectedPlate(PlateType.parkingCompleted, userName);

    if (selectedPlate != null) {
      movementPlate
          .setDepartureRequested(
        selectedPlate.plateNumber,
        selectedPlate.area,
        selectedPlate.location,
      )
          .then((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          Navigator.pop(context);
          showSuccessSnackbar(context, "출차 요청이 완료되었습니다.");
        });
      }).catchError((e) {
        if (!mounted) return;
        showFailedSnackbar(context, "출차 요청 중 오류: $e");
      });
    }
  }

  // ✅ (빌드 에러 방지) 컨트롤 버튼에서 요구하는 입차 요청 콜백 스텁
  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    _log('stub: entry parking request $plateNumber ($area)');
    showSuccessSnackbar(context, "입차 요청 처리: $plateNumber ($area)");
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 시스템/뒤로가기 처리: 선택/모드 단계적으로 해제
      onWillPop: () async {
        final plateState = context.read<MinorPlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.minorGetSelectedPlate(PlateType.parkingCompleted, userName);

        // 선택된 번호판이 있으면 선택 해제 먼저
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

        // plateList → locationPicker(table) → status 순으로 한 단계씩 되돌기
        if (_mode == MinorParkingViewMode.plateList) {
          setState(() => _mode = MinorParkingViewMode.locationPicker);
          _log('back → locationPicker(table)');
          return false;
        } else if (_mode == MinorParkingViewMode.locationPicker) {
          setState(() => _mode = MinorParkingViewMode.status);
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
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),

        // ✅ 핵심: body는 bottomNavigationBar 위 영역까지만 자동 레이아웃
        body: _buildBody(context),

        // ✅ 요구사항: ControlButtons는 항상 보이기
        bottomNavigationBar: MinorParkingCompletedControlButtons(
          isParkingAreaMode: _mode == MinorParkingViewMode.plateList,
          isStatusMode: _mode == MinorParkingViewMode.status,

          // ✅ locationPicker(=실시간 테이블) 모드에서도 ControlButtons가 “테이블용 3아이템”을 그리도록 true
          isLocationPickerMode: _mode == MinorParkingViewMode.locationPicker,

          isSorted: _isSorted,
          onToggleViewMode: _toggleViewMode,
          showSearchDialog: () => _showSearchDialog(context),
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _minorHandleDepartureRequested,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final plateState = context.watch<MinorPlateState>();
    final userName = context.read<UserState>().name;

    switch (_mode) {
      case MinorParkingViewMode.status:
      // ✅ 리셋마다 키가 바뀌어 ParkingStatusPage의 State가 새로 만들어짐 → 집계 재실행
        return MinorParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case MinorParkingViewMode.locationPicker:
      // ✅ (리팩터링) 기존 주차구역 리스트 대신 “실시간(view) 테이블 3탭”을 body에 임베드
      // ✅ ControlButtons는 계속 보이므로, LocationPicker는 그 상단까지만 차지하게 됨
        return MinorParkingCompletedRealTimeTable(
          onClose: () {
            if (!mounted) return;
            setState(() => _mode = MinorParkingViewMode.status);
          },
        );

      case MinorParkingViewMode.plateList:
      // 🔹 기존 plateList 화면은 보존(다른 경로에서 필요할 수 있음). 현재 기본 흐름에선 사용 안 함.
        List<PlateModel> plates = plateState.minorGetPlatesByCollection(PlateType.parkingCompleted);
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
                context.read<MinorPlateState>().minorTogglePlateIsSelected(
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
