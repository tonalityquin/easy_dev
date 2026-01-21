import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/triple_plate_state.dart';
import '../../../states/plate/movement_plate.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

// import '../../utils/usage_reporter.dart';

import '../../../widgets/navigation/triple_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/triple_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'parking_completed_package/triple_parking_completed_control_buttons.dart';
import 'parking_completed_package/triple_parking_completed_location_picker.dart';
import 'parking_completed_package/triple_parking_status_page.dart';

enum TripleParkingViewMode { status, locationPicker, plateList }

class TripleParkingCompletedPage extends StatefulWidget {
  const TripleParkingCompletedPage({super.key});

  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _TripleParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<TripleParkingCompletedPage> createState() => _TripleParkingCompletedPageState();
}

class _TripleParkingCompletedPageState extends State<TripleParkingCompletedPage> {
  TripleParkingViewMode _mode = TripleParkingViewMode.status; // 기본은 현황 화면
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
      _mode = TripleParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _statusKeySeed++; // ✅ Status 재생성 트리거 → ParkingStatusPage 집계 재실행
    });
    _log('reset page state');
  }

  /// ✅ 현황 모드 ↔ 테이블 모드 토글
  /// - 현황 모드: TripleParkingStatusPage
  /// - 테이블 모드: (리팩터링) TripleParkingCompletedLocationPicker = 실시간(view) 테이블(입차완료/출차요청)
  void _toggleViewMode() {
    if (_mode == TripleParkingViewMode.plateList) return; // 안전장치

    setState(() {
      _mode = (_mode == TripleParkingViewMode.status)
          ? TripleParkingViewMode.locationPicker
          : TripleParkingViewMode.status;
    });

    _log(_mode == TripleParkingViewMode.status ? 'mode → status' : 'mode → locationPicker(table)');
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
        return TripleParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  // ✅ 출차 요청 핸들러 (기존 로직 유지)
  void _tripleHandleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>();
    final userName = context.read<UserState>().name;
    final plateState = context.read<TriplePlateState>();
    final selectedPlate = plateState.tripleGetSelectedPlate(PlateType.parkingCompleted, userName);

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
  // ※ 트리플 모드에서는 입차 요청 기능이 없지만, 기존 UI/바텀시트 시그니처 호환을 위해 유지
  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    _log('stub: entry parking request $plateNumber ($area)');
    showSuccessSnackbar(context, "입차 요청 처리: $plateNumber ($area)");
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 시스템/뒤로가기 처리: 선택/모드 단계적으로 해제
      onWillPop: () async {
        final plateState = context.read<TriplePlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.tripleGetSelectedPlate(PlateType.parkingCompleted, userName);

        // 선택된 번호판이 있으면 선택 해제 먼저
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

        // plateList → locationPicker → status 순으로 한 단계씩 되돌기
        if (_mode == TripleParkingViewMode.plateList) {
          setState(() => _mode = TripleParkingViewMode.locationPicker);
          _log('back → locationPicker');
          return false;
        } else if (_mode == TripleParkingViewMode.locationPicker) {
          setState(() => _mode = TripleParkingViewMode.status);
          _log('back → status');
          return false;
        }

        // 최상위(status)면 pop 허용
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const TripleTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildBody(context),

        // ✅ 요구사항 유지: ControlButtons 항상 표시
        bottomNavigationBar: TripleParkingCompletedControlButtons(
          isParkingAreaMode: _mode == TripleParkingViewMode.plateList,
          isStatusMode: _mode == TripleParkingViewMode.status,
          isLocationPickerMode: _mode == TripleParkingViewMode.locationPicker,
          isSorted: _isSorted,
          onToggleViewMode: _toggleViewMode,
          showSearchDialog: () => _showSearchDialog(context),
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _tripleHandleDepartureRequested,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final plateState = context.watch<TriplePlateState>();
    final userName = context.read<UserState>().name;

    switch (_mode) {
      case TripleParkingViewMode.status:
      // ✅ 리셋마다 키가 바뀌어 ParkingStatusPage의 State가 새로 만들어짐 → 집계 재실행
        return TripleParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case TripleParkingViewMode.locationPicker:
      // ✅ 리팩터링: 기존 “주차 구역 리스트” 대신
      //    트리플 모드 전용 “실시간(view) 테이블(입차 완료 / 출차 요청)” 임베드 출력
      // ✅ 내부 Scaffold 제거된 위젯이므로 body 영역을 자연스럽게 채우고,
      //    bottomNavigationBar(ControlButtons) 상단까지만 렌더링됨.
        return TripleParkingCompletedLocationPicker(
          onClose: () {
            if (!mounted) return;
            setState(() => _mode = TripleParkingViewMode.status);
          },
        );

      case TripleParkingViewMode.plateList:
      // 🔹 기존 plateList 화면은 보존(다른 경로에서 필요할 수 있음). 현재 기본 흐름에선 사용 안 함.
        List<PlateModel> plates = plateState.tripleGetPlatesByCollection(PlateType.parkingCompleted);
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
                context.read<TriplePlateState>().tripleTogglePlateIsSelected(
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
