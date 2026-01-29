import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/minor_plate_state.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

import '../../../widgets/navigation/minor_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/minor_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'parking_completed_package/minor_parking_completed_real_time_table.dart';
import 'parking_completed_package/minor_parking_status_page.dart';

enum MinorParkingViewMode { status, locationPicker, plateList }

class MinorParkingCompletedPage extends StatefulWidget {
  const MinorParkingCompletedPage({super.key});

  /// ✅ 상위(MinorTypePage)에서 하단 컨트롤바가 현재 모드/정렬 상태를 알 수 있도록 노출
  static final ValueNotifier<MinorParkingViewMode> modeNotifier =
  ValueNotifier<MinorParkingViewMode>(MinorParkingViewMode.status);

  static final ValueNotifier<bool> isSortedNotifier = ValueNotifier<bool>(true);

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

  /// ✅ 외부에서 정렬 토글(plateList용)
  static void toggleSortIcon(GlobalKey key) {
    (key.currentState as _MinorParkingCompletedPageState?)?._toggleSortIcon();
  }

  @override
  State<MinorParkingCompletedPage> createState() => _MinorParkingCompletedPageState();
}

class _MinorParkingCompletedPageState extends State<MinorParkingCompletedPage> {
  MinorParkingViewMode _mode = MinorParkingViewMode.status;
  String? _selectedParkingArea;
  bool _isSorted = true;

  int _statusKeySeed = 0;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  void _syncNotifiers() {
    MinorParkingCompletedPage.modeNotifier.value = _mode;
    MinorParkingCompletedPage.isSortedNotifier.value = _isSorted;
  }

  @override
  void initState() {
    super.initState();
    _syncNotifiers();
  }

  void _resetInternalState() {
    setState(() {
      _mode = MinorParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _statusKeySeed++;
    });
    _syncNotifiers();
    _log('reset page state');
  }

  void _toggleViewMode() {
    if (_mode == MinorParkingViewMode.plateList) return;

    setState(() {
      _mode = (_mode == MinorParkingViewMode.status)
          ? MinorParkingViewMode.locationPicker
          : MinorParkingViewMode.status;
    });
    _syncNotifiers();

    _log(_mode == MinorParkingViewMode.status ? 'mode → status' : 'mode → locationPicker(table)');
  }

  void _toggleSortIcon() {
    setState(() => _isSorted = !_isSorted);
    _syncNotifiers();
    _log(_isSorted ? 'sort → 최신순' : 'sort → 오래된순');
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

        if (_mode == MinorParkingViewMode.plateList) {
          setState(() => _mode = MinorParkingViewMode.locationPicker);
          _syncNotifiers();
          _log('back → locationPicker(table)');
          return false;
        } else if (_mode == MinorParkingViewMode.locationPicker) {
          setState(() => _mode = MinorParkingViewMode.status);
          _syncNotifiers();
          _log('back → status');
          return false;
        }

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
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final plateState = context.watch<MinorPlateState>();
    final userName = context.read<UserState>().name;

    switch (_mode) {
      case MinorParkingViewMode.status:
        return MinorParkingStatusPage(
          key: ValueKey('status-$_statusKeySeed'),
        );

      case MinorParkingViewMode.locationPicker:
        return MinorParkingCompletedRealTimeTable(
          onClose: () {
            if (!mounted) return;
            setState(() => _mode = MinorParkingViewMode.status);
            _syncNotifiers();
          },
        );

      case MinorParkingViewMode.plateList:
        List<PlateModel> plates =
        plateState.minorGetPlatesByCollection(PlateType.parkingCompleted);

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
