import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/double_plate_state.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

import '../../../widgets/navigation/double_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/double_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'parking_completed_package/double_parking_completed_real_time_table.dart';
import 'parking_completed_package/double_parking_status_page.dart';

enum DoubleParkingViewMode { status, locationPicker, plateList }

class DoubleParkingCompletedPage extends StatefulWidget {
  const DoubleParkingCompletedPage({super.key});

  /// ✅ 상위(DoubleTypePage)에서 하단 컨트롤바가 현재 모드/정렬 상태를 알 수 있도록 노출
  static final ValueNotifier<DoubleParkingViewMode> modeNotifier =
  ValueNotifier<DoubleParkingViewMode>(DoubleParkingViewMode.status);

  static final ValueNotifier<bool> isSortedNotifier = ValueNotifier<bool>(true);

  /// 기존 홈 재탭 reset 유지
  static void reset(GlobalKey key) {
    (key.currentState as _DoubleParkingCompletedPageState?)?._resetInternalState();
  }

  /// ✅ 외부(상위 Scaffold)에서 '현황 ↔ 테이블' 토글 제어
  static void toggleViewMode(GlobalKey key) {
    (key.currentState as _DoubleParkingCompletedPageState?)?._toggleViewMode();
  }

  /// ✅ 외부에서 검색 다이얼로그 오픈
  static void openSearchDialog(GlobalKey key, BuildContext context) {
    (key.currentState as _DoubleParkingCompletedPageState?)?._showSearchDialog(context);
  }

  /// ✅ 외부에서 정렬 토글(plateList용)
  static void toggleSortIcon(GlobalKey key) {
    (key.currentState as _DoubleParkingCompletedPageState?)?._toggleSortIcon();
  }

  @override
  State<DoubleParkingCompletedPage> createState() => _DoubleParkingCompletedPageState();
}

class _DoubleParkingCompletedPageState extends State<DoubleParkingCompletedPage> {
  DoubleParkingViewMode _mode = DoubleParkingViewMode.status;
  String? _selectedParkingArea;
  bool _isSorted = true;

  int _statusKeySeed = 0;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  void _syncNotifiers() {
    DoubleParkingCompletedPage.modeNotifier.value = _mode;
    DoubleParkingCompletedPage.isSortedNotifier.value = _isSorted;
  }

  @override
  void initState() {
    super.initState();
    _syncNotifiers();
  }

  void _resetInternalState() {
    setState(() {
      _mode = DoubleParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _statusKeySeed++;
    });
    _syncNotifiers();
    _log('reset page state');
  }

  void _toggleViewMode() {
    if (_mode == DoubleParkingViewMode.plateList) return;

    setState(() {
      _mode = (_mode == DoubleParkingViewMode.status)
          ? DoubleParkingViewMode.locationPicker
          : DoubleParkingViewMode.status;
    });
    _syncNotifiers();

    _log(_mode == DoubleParkingViewMode.status ? 'mode → status' : 'mode → locationPicker(table)');
  }

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
    _syncNotifiers();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        final plateState = context.read<DoublePlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate =
        plateState.doubleGetSelectedPlate(PlateType.parkingCompleted, userName);

        // ✅ 선택된 차량이 있으면 "뒤로가기 = 선택 해제" 우선
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

        // ✅ 내부 모드 back 처리(plateList → locationPicker → status)
        if (_mode == DoubleParkingViewMode.plateList) {
          setState(() => _mode = DoubleParkingViewMode.locationPicker);
          _syncNotifiers();
          _log('back → locationPicker');
          return false;
        } else if (_mode == DoubleParkingViewMode.locationPicker) {
          setState(() => _mode = DoubleParkingViewMode.status);
          _syncNotifiers();
          _log('back → status');
          return false;
        }

        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const DoubleTopNavigation(),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
          ),
        ),

        // ✅ 변경 핵심: 기존 bottomNavigationBar 제거 → 그 높이만큼 body 영역 확보
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final plateState = context.watch<DoublePlateState>();
    final userName = context.read<UserState>().name;

    switch (_mode) {
      case DoubleParkingViewMode.status:
        return DoubleParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case DoubleParkingViewMode.locationPicker:
        return DoubleParkingCompletedRealTimeTable(
          onClose: () {
            if (!mounted) return;
            setState(() => _mode = DoubleParkingViewMode.status);
            _syncNotifiers();
          },
        );

      case DoubleParkingViewMode.plateList:
        List<PlateModel> plates =
        plateState.doubleGetPlatesByCollection(PlateType.parkingCompleted);

        if (_selectedParkingArea != null) {
          plates = plates.where((p) => p.location == _selectedParkingArea).toList();
        }

        plates.sort(
              (a, b) => _isSorted
              ? b.requestTime.compareTo(a.requestTime)
              : a.requestTime.compareTo(b.requestTime),
        );

        return ListView(
          padding: const EdgeInsets.all(8.0),
          children: [
            PlateContainer(
              data: plates,
              collection: PlateType.parkingCompleted,
              filterCondition: (request) =>
              request.type == PlateType.parkingCompleted.firestoreValue,
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
