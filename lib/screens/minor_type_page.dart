import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/minor_page_state.dart';
import '../states/plate/minor_plate_state.dart';
import '../states/user/user_state.dart';

import 'minor_mode/input_package/minor_input_plate_screen.dart';
import 'minor_mode/type_package/common_widgets/dashboard_bottom_sheet/minor_home_dash_board_bottom_sheet.dart';
import 'minor_mode/type_package/minor_parking_completed_page.dart';
import 'minor_mode/type_package/parking_completed_package/minor_parking_completed_control_buttons.dart';

import '../utils/snackbar_helper.dart';

// ✅ Trace 기록용 Recorder
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';
import '../services/driving_recovery/driving_recovery_gate.dart';

class MinorTypePage extends StatefulWidget {
  const MinorTypePage({super.key});

  @override
  State<MinorTypePage> createState() => _MinorTypePageState();
}

class _MinorTypePageState extends State<MinorTypePage> {
  @override
  void initState() {
    super.initState();

    // ✅ Minor 진입: MinorPlateState만 1회 로드(get)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MinorPlateState>().minorEnableForTypePages(withDefaults: true);
    });
  }

  @override
  void dispose() {
    // ✅ Minor 이탈: 로드/보류 상태 정리
    try {
      context.read<MinorPlateState>().minorDisableAll();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MinorPageState>(
      create: (_) => MinorPageState(),
      child: Builder(
        builder: (context) {
          final plateState = context.read<MinorPlateState>();
          final pageState = context.read<MinorPageState>();
          final userName = context.read<UserState>().name;

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) async {
              if (didPop) return;

              final currentPage = pageState.pages[pageState.selectedIndex];
              final collection = currentPage.collectionKey;
              final selected = plateState.minorGetSelectedPlate(collection, userName);

              if (selected != null && selected.id.isNotEmpty) {
                await plateState.minorTogglePlateIsSelected(
                  collection: collection,
                  plateNumber: selected.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
              }
            },
            child: Scaffold(
              body: DrivingRecoveryGate(
                mode: DrivingRecoveryMode.minor,
                child: const RefreshableBody(),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    // ✅ 1행: 모드 토글(현황/테이블) + 출차요청(count) + 출차완료
                    _ParkingCompletedControlBar(),

                    // ✅ 2행: 입차/대시보드
                    _EntryDashboardBar(),

                    // ✅ 3행: 홈
                    _SingleHomeTabBar(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ✅ MinorParkingCompletedPage의 모드(현황/테이블)를 하단 컨트롤바에 반영.
/// - modeNotifier로 동기화.
/// - 컨트롤 위젯 리팩터링으로 레거시 인자(정렬/사전정산/상태수정/삭제/요청확정 등) 제거됨.
class _ParkingCompletedControlBar extends StatelessWidget {
  const _ParkingCompletedControlBar();

  @override
  Widget build(BuildContext context) {
    final pageState = context.read<MinorPageState>();

    return ValueListenableBuilder<MinorParkingViewMode>(
      valueListenable: MinorParkingCompletedPage.modeNotifier,
      builder: (context, mode, _) {
        final isStatusMode = mode == MinorParkingViewMode.status;

        return MinorParkingCompletedControlButtons(
          isStatusMode: isStatusMode,
          onToggleViewMode: () {
            MinorParkingCompletedPage.toggleViewMode(pageState.parkingCompletedKey);
          },
          showSearchDialog: () {
            MinorParkingCompletedPage.openSearchDialog(
              pageState.parkingCompletedKey,
              context,
            );
          },
        );
      },
    );
  }
}

class _EntryDashboardBar extends StatelessWidget {
  const _EntryDashboardBar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          // 좌측: 입차 화면 열기
          const Expanded(child: _OpenEntryButton()),
          const SizedBox(width: 8),

          // 우측: 대시보드
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const MinorHomeDashBoardBottomSheet(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
                shadowColor: cs.shadow.withOpacity(0.25),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dashboard, size: 20),
                  SizedBox(width: 6),
                  Text('대시보드'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenEntryButton extends StatelessWidget {
  const _OpenEntryButton();

  void _trace(BuildContext context, String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _openEntryScreen(BuildContext context) async {
    Navigator.of(context).push(
      _slidePageRoute(const MinorInputPlateScreen(), fromLeft: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton(
      onPressed: () async {
        _trace(
          context,
          '입차 화면 열기 버튼',
          meta: <String, dynamic>{
            'screen': 'minor_type_page',
            'action': 'open_minor_input_plate_screen',
          },
        );
        await _openEntryScreen(context);
      },
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
        ),
      ).copyWith(
        overlayColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => states.contains(MaterialState.pressed)
              ? cs.outlineVariant.withOpacity(0.12)
              : null,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            '입차',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleHomeTabBar extends StatelessWidget {
  const _SingleHomeTabBar();

  void _trace(BuildContext context, String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<MinorPageState>(
      builder: (context, pageState, _) {
        return SizedBox(
          height: kBottomNavigationBarHeight,
          child: Material(
            color: cs.surface,
            child: InkWell(
              onTap: () async {
                _trace(
                  context,
                  '홈 버튼',
                  meta: <String, dynamic>{
                    'screen': 'minor_type_page',
                    'action': 'home_tap',
                    'targetIndex': 0,
                    'selectedIndexBefore': pageState.selectedIndex,
                  },
                );

                await pageState.onItemTapped(
                  context,
                  0,
                  onError: (msg) => showFailedSnackbar(context, msg),
                );

                // 홈 탭할 때마다 데이터 1회 get
                try {
                  context.read<MinorPlateState>().minorSyncWithAreaState();
                } catch (_) {}

                // 출차요청(및 현재 코드상 입차요청도 동일 토큰 사용) aggregation refresh 토큰 bump
                pageState.bumpDepartureRequestsCountRefreshToken();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.home, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '홈',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class RefreshableBody extends StatefulWidget {
  const RefreshableBody({super.key});

  @override
  State<RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<RefreshableBody> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer2<MinorPageState, MinorPlateState>(
      builder: (context, pageState, plateState, _) {
        return Stack(
          children: [
            _buildCurrentPage(context, pageState),
            if (plateState.isLoading)
              Container(
                color: cs.surface.withOpacity(.35),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCurrentPage(BuildContext context, MinorPageState state) {
    final pageInfo = state.pages[state.selectedIndex];
    return pageInfo.builder(context);
  }
}

/// ✅ 공용 슬라이드 라우트
PageRouteBuilder _slidePageRoute(Widget page, {required bool fromLeft}) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final begin = Offset(fromLeft ? -1.0 : 1.0, 0);
      final end = Offset.zero;
      final tween = Tween(begin: begin, end: end).chain(
        CurveTween(curve: Curves.easeInOut),
      );
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}
