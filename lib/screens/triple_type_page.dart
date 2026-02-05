import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/triple_page_state.dart';
import '../states/area/area_state.dart';
import '../states/plate/triple_plate_state.dart';
import '../states/user/user_state.dart';

import 'triple_mode/input_package/triple_input_plate_screen.dart';
import 'triple_mode/type_package/common_widgets/dashboard_bottom_sheet/triple_home_dash_board_bottom_sheet.dart';
import 'triple_mode/type_package/triple_parking_completed_page.dart';
import 'triple_mode/type_package/parking_completed_package/triple_parking_completed_control_buttons.dart';

import '../utils/snackbar_helper.dart';
import '../services/latest_message_service.dart';

// ✅ Trace 기록용 Recorder
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';
import '../services/driving_recovery/driving_recovery_gate.dart';

class _Brand {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);

  static Color overlayOnSurface(ColorScheme cs) => cs.outlineVariant.withOpacity(0.12);

  static ButtonStyle outlinedSurfaceButtonStyle(
      BuildContext context, {
        double minHeight = 48,
        Color? borderColor,
      }) {
    final cs = Theme.of(context).colorScheme;
    final bc = borderColor ?? border(cs);

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      minimumSize: Size.fromHeight(minHeight),
      padding: EdgeInsets.zero,
      elevation: 0,
      side: BorderSide(color: bc, width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed) ? overlayOnSurface(cs) : null,
      ),
    );
  }

  static ButtonStyle filledPrimaryButtonStyle(
      BuildContext context, {
        double minHeight = 48,
      }) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      minimumSize: Size.fromHeight(minHeight),
      padding: EdgeInsets.zero,
      elevation: 2,
      shadowColor: cs.shadow.withOpacity(0.20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
            ? cs.onPrimary.withOpacity(0.12)
            : null,
      ),
    );
  }
}

class TripleTypePage extends StatefulWidget {
  const TripleTypePage({super.key});

  @override
  State<TripleTypePage> createState() => _TripleTypePageState();
}

class _TripleTypePageState extends State<TripleTypePage> {
  @override
  void initState() {
    super.initState();

    // ✅ Triple 진입: TriplePlateState만 1회 로드(get) 수행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TriplePlateState>().tripleEnableForTypePages(withDefaults: true);
    });
  }

  @override
  void dispose() {
    // ✅ Triple 이탈: 로드/보류 상태 정리
    try {
      context.read<TriplePlateState>().tripleDisableAll();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TriplePageState>(
      create: (_) => TriplePageState(),
      child: Builder(
        builder: (context) {
          final normalPlateState = context.read<TriplePlateState>();
          final pageState = context.read<TriplePageState>();
          final userName = context.read<UserState>().name;

          // ★ 현재 area 기반으로 전역 리스너 시작 — idempotent
          final currentArea = context.read<AreaState>().currentArea.trim();
          if (currentArea.isNotEmpty) {
            LatestMessageService.instance.start(currentArea);
          }

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) async {
              if (didPop) return;

              final currentPage = pageState.pages[pageState.selectedIndex];
              final collection = currentPage.collectionKey;
              final normalSelectedPlate =
              normalPlateState.tripleGetSelectedPlate(collection, userName);

              if (normalSelectedPlate != null && normalSelectedPlate.id.isNotEmpty) {
                await normalPlateState.tripleTogglePlateIsSelected(
                  collection: collection,
                  plateNumber: normalSelectedPlate.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
              }
            },
            child: Scaffold(
              body: DrivingRecoveryGate(
                mode: DrivingRecoveryMode.triple,
                child: const RefreshableBody(),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    // ✅ 1행: 현황/테이블 토글 + 출차요청(count) + 출차완료
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

/// ✅ TripleParkingCompletedPage의 모드(현황/테이블)를 하단 컨트롤바에 반영.
/// - modeNotifier로 동기화.
/// - 컨트롤 위젯 리팩터링으로 레거시 인자(정렬/입차요청/사전정산/상태수정 등) 제거됨.
class _ParkingCompletedControlBar extends StatelessWidget {
  const _ParkingCompletedControlBar();

  @override
  Widget build(BuildContext context) {
    final pageState = context.read<TriplePageState>();

    return ValueListenableBuilder<TripleParkingViewMode>(
      valueListenable: TripleParkingCompletedPage.modeNotifier,
      builder: (context, mode, _) {
        final isStatusMode = mode == TripleParkingViewMode.status;

        return TripleParkingCompletedControlButtons(
          isStatusMode: isStatusMode,
          onToggleViewMode: () {
            TripleParkingCompletedPage.toggleViewMode(pageState.parkingCompletedKey);
          },
          showSearchDialog: () {
            TripleParkingCompletedPage.openSearchDialog(
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          // ✅ 좌측: 입차 화면 열기 버튼
          const Expanded(child: _OpenEntryButton()),
          const SizedBox(width: 8),

          // ✅ 우측: 대시보드 버튼
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const TripleHomeDashBoardBottomSheet(),
                );
              },
              style: _Brand.filledPrimaryButtonStyle(context, minHeight: 48),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dashboard, size: 20),
                  SizedBox(width: 6),
                  Text('대시보드', style: TextStyle(fontWeight: FontWeight.w900)),
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
      _slidePageRoute(const TripleInputPlateScreen(), fromLeft: true),
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
            'screen': 'triple_type_page',
            'action': 'open_triple_input_plate_screen',
          },
        );

        await _openEntryScreen(context);
      },
      style: _Brand.outlinedSurfaceButtonStyle(
        context,
        minHeight: 48,
        borderColor: cs.primary.withOpacity(0.35),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            '입차',
            style: TextStyle(
              fontWeight: FontWeight.w900,
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

    return Consumer<TriplePageState>(
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
                    'screen': 'triple_type_page',
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

                // ✅ 홈 버튼 탭 시 데이터 갱신
                try {
                  context.read<TriplePlateState>().tripleSyncWithAreaState();
                } catch (_) {}

                // ✅ 같은 area에서도 출차요청 aggregation count 재조회 트리거
                pageState.bumpDepartureRequestsCountRefreshToken();
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: _Brand.border(cs)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.home, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      '홈',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
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

    return Consumer2<TriplePageState, TriplePlateState>(
      builder: (context, pageState, normalPlateState, _) {
        return Stack(
          children: [
            _buildCurrentPage(context, pageState),
            if (normalPlateState.isLoading)
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

  Widget _buildCurrentPage(BuildContext context, TriplePageState state) {
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
      final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOut));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}
