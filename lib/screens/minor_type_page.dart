import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/minor_page_state.dart';
import '../states/plate/minor_plate_state.dart';
import '../states/user/user_state.dart';

import 'minor_mode/input_package/minor_input_plate_screen.dart';
import 'minor_mode/type_package/common_widgets/dashboard_bottom_sheet/minor_home_dash_board_bottom_sheet.dart';
import '../utils/snackbar_helper.dart';

// ✅ AppCardPalette ThemeExtension 사용
import '../theme.dart';

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

    // ✅ Minor 진입: PlateState 절대 금지(구독 시작됨)
    // ✅ MinorPlateState만 1회 로드(get) 수행
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
              final normalSelectedPlate = plateState.minorGetSelectedPlate(collection, userName);

              if (normalSelectedPlate != null && normalSelectedPlate.id.isNotEmpty) {
                await plateState.minorTogglePlateIsSelected(
                  collection: collection,
                  plateNumber: normalSelectedPlate.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
              }
            },
            child: Scaffold(
              body: DrivingRecoveryGate(mode: DrivingRecoveryMode.minor, child: const RefreshableBody()),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _EntryDashboardBar(),
                    const _SingleHomeTabBar(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        height: 48,
                        child: Image.asset('assets/images/pelican.png'),
                      ),
                    ),
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

class _EntryDashboardBar extends StatelessWidget {
  const _EntryDashboardBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          // ✅ 좌측: 입차 화면 열기 버튼
          const Expanded(
            child: _OpenEntryButton(),
          ),
          const SizedBox(width: 8),

          // ── 대시보드(기존)
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
                backgroundColor: palette.tripleBase,
                foregroundColor: palette.tripleLight,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
                shadowColor: palette.tripleDark.withOpacity(.25),
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
    final palette = AppCardPalette.of(context);

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
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppCardPalette.of(context).tripleBase.withOpacity(.35)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, size: 20, color: palette.tripleBase),
          const SizedBox(width: 8),
          Text(
            '입차',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: palette.tripleBase,
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleHomeTabBar extends StatelessWidget {
  const _SingleHomeTabBar();

  // ✅ 공통 Trace 기록 헬퍼 (StatelessWidget용)
  void _trace(BuildContext context, String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return Consumer<MinorPageState>(
      builder: (context, pageState, _) {
        return SizedBox(
          height: kBottomNavigationBarHeight,
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: () async {
                // ✅ 홈 버튼 탭 Trace 기록
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

                // ✅ (기존) 홈 탭 처리: 재탭이면 reset 수행
                await pageState.onItemTapped(
                  context,
                  0,
                  onError: (msg) => showFailedSnackbar(context, msg),
                );

                // ✅ (기존 유지) 홈 버튼을 탭할 때마다 데이터 갱신(1회 조회 get)
                try {
                  context.read<MinorPlateState>().minorSyncWithAreaState();
                } catch (_) {
                  // no-op
                }

                // ✅ [추가] 같은 area에서도 출차요청 aggregation count 재조회 트리거
                // - 내부에 0.8초 쿨다운(Throttle) 적용됨
                pageState.bumpDepartureRequestsCountRefreshToken();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.home, color: palette.tripleBase),
                  const SizedBox(width: 8),
                  Text(
                    '홈',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: palette.tripleBase,
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
    final palette = AppCardPalette.of(context);

    // ✅ [변경] Vertical Drag(TopSheet) 제스처 로직 완전 제거
    return Consumer2<MinorPageState, MinorPlateState>(
      builder: (context, pageState, plateState, _) {
        return Stack(
          children: [
            _buildCurrentPage(context, pageState),
            if (plateState.isLoading)
              Container(
                color: Colors.white.withOpacity(.35),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(palette.tripleBase),
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

/// ✅ 공용 슬라이드 라우트(중복 제거)
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
