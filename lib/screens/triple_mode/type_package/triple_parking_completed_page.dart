import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../states/plate/triple_plate_state.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

// import '../../utils/usage_reporter.dart';

import '../../../widgets/navigation/triple_top_navigation.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/triple_parking_completed_search_bottom_sheet.dart';
import '../../../widgets/container/plate_container.dart';

import 'parking_completed_package/triple_parking_completed_real_time_table.dart';
import 'parking_completed_package/triple_parking_status_page.dart';

enum TripleParkingViewMode { status, locationPicker, plateList }

class TripleParkingCompletedPage extends StatefulWidget {
  const TripleParkingCompletedPage({super.key});

  /// ✅ 상위(TripleTypePage)에서 하단 컨트롤바가 현재 모드/정렬 상태를 알 수 있도록 노출
  static final ValueNotifier<TripleParkingViewMode> modeNotifier =
  ValueNotifier<TripleParkingViewMode>(TripleParkingViewMode.status);

  static final ValueNotifier<bool> isSortedNotifier = ValueNotifier<bool>(true);

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

  /// ✅ 외부에서 정렬 토글(plateList용)
  static void toggleSortIcon(GlobalKey key) {
    (key.currentState as _TripleParkingCompletedPageState?)?._toggleSortIcon();
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

  void _syncNotifiers() {
    TripleParkingCompletedPage.modeNotifier.value = _mode;
    TripleParkingCompletedPage.isSortedNotifier.value = _isSorted;
  }

  @override
  void initState() {
    super.initState();
    _syncNotifiers();
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
    _syncNotifiers();
    _log('reset page state');
  }

  /// ✅ 현황 모드 ↔ 테이블 모드 토글
  /// - 현황 모드: TripleParkingStatusPage
  /// - 테이블 모드: 실시간(view) 테이블(입차완료/출차요청)
  void _toggleViewMode() {
    if (_mode == TripleParkingViewMode.plateList) return; // 안전장치

    setState(() {
      _mode = (_mode == TripleParkingViewMode.status)
          ? TripleParkingViewMode.locationPicker
          : TripleParkingViewMode.status;
    });
    _syncNotifiers();

    _log(_mode == TripleParkingViewMode.status
        ? 'mode → status'
        : 'mode → locationPicker(table)');
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
        return TripleParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  // ✅ (빌드 에러 방지) 컨트롤 버튼에서 요구하는 입차 요청 콜백 스텁
  // ※ 트리플 모드에서는 입차 요청 기능이 없지만, 기존 UI/바텀시트 시그니처 호환을 위해 유지
  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    _log('stub: entry parking request $plateNumber ($area)');
    showSuccessSnackbar(context, "입차 요청 처리: $plateNumber ($area)");
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      // 시스템/뒤로가기 처리: 선택/모드 단계적으로 해제
      onWillPop: () async {
        final plateState = context.read<TriplePlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate =
        plateState.tripleGetSelectedPlate(PlateType.parkingCompleted, userName);

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
          _syncNotifiers();
          _log('back → locationPicker');
          return false;
        } else if (_mode == TripleParkingViewMode.locationPicker) {
          setState(() => _mode = TripleParkingViewMode.status);
          _syncNotifiers();
          _log('back → status');
          return false;
        }

        // 최상위(status)면 pop 허용
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
        // 기존 bottomNavigationBar(TripleParkingCompletedControlButtons) 제거
        // → 그 높이만큼 ParkingCompletedPage의 body 영역 확장
        body: _buildBody(context),
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
        return TripleParkingCompletedRealTimeTable(
          onClose: () {
            if (!mounted) return;
            setState(() => _mode = TripleParkingViewMode.status);
            _syncNotifiers();
          },
        );

      case TripleParkingViewMode.plateList:
      // 🔹 기존 plateList 화면은 보존(다른 경로에서 필요할 수 있음). 현재 기본 흐름에선 사용 안 함.
        List<PlateModel> plates =
        plateState.tripleGetPlatesByCollection(PlateType.parkingCompleted);

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
