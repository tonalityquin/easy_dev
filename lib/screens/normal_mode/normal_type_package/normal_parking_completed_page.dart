import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/normal_plate_state.dart';
import '../../../states/plate/movement_plate.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

// import '../../utils/usage_reporter.dart';

import '../../../widgets/navigation/normal_top_navigation.dart';
import 'normal_parking_completed_package/widgets/signature_plate_search_bottom_sheet/normal_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'normal_parking_completed_package/normal_parking_completed_control_buttons.dart';
import 'normal_parking_completed_package/normal_parking_completed_location_picker.dart';
import 'normal_parking_completed_package/normal_parking_status_page.dart';

enum NormalParkingViewMode { status, locationPicker, plateList }

class NormalParkingCompletedPage extends StatefulWidget {
  const NormalParkingCompletedPage({super.key});

  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _NormalParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<NormalParkingCompletedPage> createState() => _NormalParkingCompletedPageState();
}

class _NormalParkingCompletedPageState extends State<NormalParkingCompletedPage> {
  NormalParkingViewMode _mode = NormalParkingViewMode.status; // 기본은 현황 화면
  String? _selectedParkingArea; // 선택된 주차 구역(location) (plateList 보존용)
  bool _isSorted = true; // true=최신순
  bool _isLocked = true; // 화면 잠금

  // ✅ Status 페이지 강제 재생성용 키 시드 (홈 버튼 리셋 시 증가)
  int _statusKeySeed = 0;

  // ─────────────────────────────────────────────────────────────
  // 로컬 로그(디버그 전용)
  // ─────────────────────────────────────────────────────────────
  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  /*void _reportReadDb(String source, {int n = 1}) {
    try {
      final area = context.read<AreaState>().currentArea.trim();
      UsageReporter.instance.report(area: area, action: 'read', n: n, source: source);
    } catch (_) {
    }
  }*/

  /// 홈 재탭/진입 시 초기 상태로 되돌림
  void _resetInternalState() {
    setState(() {
      _mode = NormalParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _isLocked = true; // ✅ 요구사항: 홈에서 다시 시작할 때 잠금 ON
      _statusKeySeed++; // ✅ Status 재생성 트리거 → ParkingStatusPage 집계 재실행
    });
    _log('reset page state');
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
        return NormalParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  // ✅ 출차 요청 핸들러 (기존 로직 유지)
  void _normalHandleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>();
    final userName = context.read<UserState>().name;
    final normalPlateState = context.read<NormalPlateState>();
    final normalSelectedPlate = normalPlateState.normalGetSelectedPlate(PlateType.parkingCompleted, userName);

    if (normalSelectedPlate != null) {
      movementPlate
          .setDepartureRequested(
        normalSelectedPlate.plateNumber,
        normalSelectedPlate.area,
        normalSelectedPlate.location,
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
        final normalPlateState = context.read<NormalPlateState>();
        final userName = context.read<UserState>().name;
        final normalSelectedPlate = normalPlateState.normalGetSelectedPlate(PlateType.parkingCompleted, userName);

        // 선택된 번호판이 있으면 선택 해제 먼저
        if (normalSelectedPlate != null && normalSelectedPlate.id.isNotEmpty) {
          await normalPlateState.normalTogglePlateIsSelected(
            collection: PlateType.parkingCompleted,
            plateNumber: normalSelectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          _log('clear selection');
          return false;
        }

        // plateList → locationPicker → status 순으로 한 단계씩 되돌기
        if (_mode == NormalParkingViewMode.plateList) {
          setState(() => _mode = NormalParkingViewMode.locationPicker);
          _log('back → locationPicker');
          return false;
        } else if (_mode == NormalParkingViewMode.locationPicker) {
          setState(() => _mode = NormalParkingViewMode.status);
          _log('back → status');
          return false;
        }

        // 최상위(status)면 pop 허용
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const NormalTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildBody(context),
        bottomNavigationBar: NormalParkingCompletedControlButtons(
          isParkingAreaMode: _mode == NormalParkingViewMode.plateList,
          isStatusMode: _mode == NormalParkingViewMode.status,
          isLocationPickerMode: _mode == NormalParkingViewMode.locationPicker,
          isSorted: _isSorted,
          isLocked: _isLocked,
          onToggleLock: () {
            setState(() {
              _isLocked = !_isLocked;
            });
            _log(_isLocked ? 'lock ON' : 'lock OFF');
          },
          showSearchDialog: () => _showSearchDialog(context),
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _normalHandleDepartureRequested,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final normalPlateState = context.watch<NormalPlateState>();
    final userName = context.read<UserState>().name;

    switch (_mode) {
      case NormalParkingViewMode.status:
      // 🔹 현황 화면을 탭하면 위치 선택 화면으로 전환
        return GestureDetector(
          onTap: () {
            setState(() => _mode = NormalParkingViewMode.locationPicker);
            _log('open location picker');
          },
          // ✅ 리셋마다 키가 바뀌어 ParkingStatusPage의 State가 새로 만들어짐 → 집계 재실행
          child: NormalParkingStatusPage(
            key: ValueKey('status-$_statusKeySeed'),
            isLocked: _isLocked,
          ),
        );

      case NormalParkingViewMode.locationPicker:
      // ✅ 요구사항: 주차 구역 선택 시 아무 동작도 하지 않음
        return NormalParkingCompletedLocationPicker(
          onLocationSelected: (_) {
            // no-op
          },
          isLocked: _isLocked,
        );

      case NormalParkingViewMode.plateList:
      // 🔹 기존 plateList 화면은 보존(다른 경로에서 필요할 수 있음). 현재 기본 흐름에선 사용 안 함.
        List<PlateModel> plates = normalPlateState.normalGetPlatesByCollection(PlateType.parkingCompleted);
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
                context.read<NormalPlateState>().normalTogglePlateIsSelected(
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
