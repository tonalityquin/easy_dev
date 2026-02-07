import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/double_page_state.dart';
import '../states/plate/double_plate_state.dart';
import '../states/user/user_state.dart';

import 'double_mode/input_package/double_input_plate_screen.dart';
import 'double_mode/type_package/common_widgets/dashboard_bottom_sheet/double_home_dash_board_bottom_sheet.dart';
import 'double_mode/type_package/double_parking_completed_page.dart';
import 'double_mode/type_package/parking_completed_package/double_parking_completed_control_buttons.dart';

import '../utils/snackbar_helper.dart';

// ✅ Trace 기록용 Recorder
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

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
            (states) => states.contains(MaterialState.pressed) ? cs.onPrimary.withOpacity(0.12) : null,
      ),
    );
  }
}

class DoubleTypePage extends StatefulWidget {
  const DoubleTypePage({super.key});

  @override
  State<DoubleTypePage> createState() => _DoubleTypePageState();
}

class _DoubleTypePageState extends State<DoubleTypePage> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DoublePlateState>().doubleEnableForTypePages(withDefaults: true);
    });
  }

  @override
  void dispose() {
    try {
      context.read<DoublePlateState>().doubleDisableAll();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DoublePageState>(
      create: (_) => DoublePageState(),
      child: Builder(
        builder: (context) {
          final litePlateState = context.read<DoublePlateState>();
          final pageState = context.read<DoublePageState>();
          final userName = context.read<UserState>().name;

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) async {
              if (didPop) return;

              final currentPage = pageState.pages[pageState.selectedIndex];
              final collection = currentPage.collectionKey;
              final liteSelectedPlate = litePlateState.doubleGetSelectedPlate(collection, userName);

              if (liteSelectedPlate != null && liteSelectedPlate.id.isNotEmpty) {
                await litePlateState.doubleTogglePlateIsSelected(
                  collection: collection,
                  plateNumber: liteSelectedPlate.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
              }
            },
            child: Scaffold(
              body: const RefreshableBody(),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    // ✅ 1행: 현황/테이블 토글 + 번호판 검색 + 출차 완료
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

/// ✅ DoubleParkingCompletedPage의 모드(현황/테이블)를 하단 컨트롤바에 반영.
/// - 모드 상태는 DoubleParkingCompletedPage.modeNotifier로 동기화.
/// - 리팩터링으로 레거시 인자(정렬/입차요청/출차요청 등) 제거됨.
class _ParkingCompletedControlBar extends StatelessWidget {
  const _ParkingCompletedControlBar();

  @override
  Widget build(BuildContext context) {
    final pageState = context.read<DoublePageState>();

    return ValueListenableBuilder<DoubleParkingViewMode>(
      valueListenable: DoubleParkingCompletedPage.modeNotifier,
      builder: (context, mode, _) {
        final isStatusMode = mode == DoubleParkingViewMode.status;

        return DoubleParkingCompletedControlButtons(
          isStatusMode: isStatusMode,
          onToggleViewMode: () {
            DoubleParkingCompletedPage.toggleViewMode(pageState.parkingCompletedKey);
          },
          showSearchDialog: () {
            DoubleParkingCompletedPage.openSearchDialog(
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
          const Expanded(child: _OpenEntryButton()),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const DoubleHomeDashBoardBottomSheet(),
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
      _slidePageRoute(const DoubleInputPlateScreen(), fromLeft: true),
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
            'screen': 'lite_type_page',
            'action': 'open_double_input_plate_screen',
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

    return Consumer<DoublePageState>(
      builder: (context, pageState, _) {
        return SizedBox(
          height: kBottomNavigationBarHeight,
          child: Material(
            color: cs.surface,
            child: InkWell(
              onTap: () {
                _trace(
                  context,
                  '홈 버튼',
                  meta: <String, dynamic>{
                    'screen': 'lite_type_page',
                    'action': 'home_tap',
                    'targetIndex': 0,
                    'selectedIndexBefore': pageState.selectedIndex,
                  },
                );

                pageState.onItemTapped(
                  context,
                  0,
                  onError: (msg) => showFailedSnackbar(context, msg),
                );
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
                      fontWeight: FontWeight.w900,
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

    return Consumer2<DoublePageState, DoublePlateState>(
      builder: (context, pageState, litePlateState, _) {
        return Stack(
          children: [
            _buildCurrentPage(context, pageState),
            if (litePlateState.isLoading)
              Container(
                // ✅ 로딩 오버레이 톤: Triple/Minor와 동일하게 surface 0.35로 통일
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

  Widget _buildCurrentPage(BuildContext context, DoublePageState state) {
    final pageInfo = state.pages[state.selectedIndex];
    return pageInfo.builder(context);
  }
}

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
