import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/triple_page_state.dart';
import '../states/area/area_state.dart';
import '../states/plate/triple_plate_state.dart';
import '../states/user/user_state.dart';

import 'triple_mode/input_package/triple_input_plate_screen.dart';
import 'triple_mode/type_package/common_widgets/dashboard_bottom_sheet/triple_home_dash_board_bottom_sheet.dart';
import 'triple_mode/type_package/common_widgets/reverse_sheet_package/triple_parking_completed_table_sheet.dart';
import '../utils/snackbar_helper.dart';

import '../services/latest_message_service.dart';

// ✅ AppCardPalette ThemeExtension 사용
import '../theme.dart';

// ✅ Trace 기록용 Recorder
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class TripleTypePage extends StatefulWidget {
  const TripleTypePage({super.key});

  @override
  State<TripleTypePage> createState() => _TripleTypePageState();
}

class _TripleTypePageState extends State<TripleTypePage> {
  @override
  void initState() {
    super.initState();

    // ✅ Triple 진입: PlateState 절대 금지(구독 시작됨)
    // ✅ TriplePlateState만 1회 로드(get) 수행
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
              body: const RefreshableBody(),
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
          // ✅ 좌측: 입차 화면 열기 버튼 (기존 채팅 버튼 제거)
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
                  builder: (_) => const TripleHomeDashBoardBottomSheet(),
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
      _slidePageRoute(const TripleInputPlateScreen(), fromLeft: true),
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
            'screen': 'triple_type_page',
            'action': 'open_triple_input_plate_screen',
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
          side: BorderSide(color: palette.tripleBase.withOpacity(.35)),
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

    return Consumer<TriplePageState>(
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
                    'screen': 'triple_type_page',
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
                  context.read<TriplePlateState>().tripleSyncWithAreaState();
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
  double _vDragDistance = 0.0;
  bool _topOpening = false;

  // ✅ 아래로 스와이프(TopSheet)만 유지
  static const double _vDistanceThresholdDown = 50.0;
  static const double _vVelocityThresholdDown = 700.0;

  Future<void> _openParkingCompletedTableSheet(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    await showTripleParkingCompletedTableTopSheet(context);
  }

  Future<void> _handleVerticalDragEnd(BuildContext context, DragEndDetails details) async {
    final vy = details.primaryVelocity ?? 0.0;

    // ✅ 아래로 스와이프(TopSheet)만 유지
    final firedDown = (_vDragDistance > _vDistanceThresholdDown) || (vy > _vVelocityThresholdDown);

    if (firedDown && !_topOpening) {
      _topOpening = true;
      await _openParkingCompletedTableSheet(context);
      _topOpening = false;
    }

    _vDragDistance = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,

      // ✅ [변경] 좌/우 가로 스와이프 기능 전체 삭제
      // onHorizontalDragUpdate: null
      // onHorizontalDragEnd: null

      onVerticalDragStart: (_) => _vDragDistance = 0.0,
      onVerticalDragUpdate: (details) => _vDragDistance += details.delta.dy,
      onVerticalDragEnd: (details) => _handleVerticalDragEnd(context, details),
      child: Consumer2<TriplePageState, TriplePlateState>(
        builder: (context, pageState, normalPlateState, _) {
          return Stack(
            children: [
              _buildCurrentPage(context, pageState),
              if (normalPlateState.isLoading)
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
      ),
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
