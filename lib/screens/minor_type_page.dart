import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/minor_page_state.dart';
import '../states/area/area_state.dart';
import '../states/plate/minor_plate_state.dart';
import '../states/user/user_state.dart';

import 'common_package/chat_package/lite_chat_bottom_sheet.dart';
import 'minor_mode/input_package/minor_input_plate_screen.dart';
import 'minor_mode/type_package/common_widgets/dashboard_bottom_sheet/minor_home_dash_board_bottom_sheet.dart';
import 'minor_mode/type_package/common_widgets/reverse_sheet_package/minor_parking_completed_table_sheet.dart';
import 'secondary_page.dart';
import '../utils/snackbar_helper.dart';

import '../services/latest_message_service.dart';

// ✅ AppCardPalette ThemeExtension 사용
import '../theme.dart';

// ✅ Trace 기록용 Recorder
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

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
    // ✅ Triple 이탈: 로드/보류 상태 정리
    try {
      context.read<MinorPlateState>().minorDisableAll();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MinorPageState(),
      child: Builder(
        builder: (context) {
          final normalPlateState = context.read<MinorPlateState>();
          final pageState = context.read<MinorPageState>();
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
              final normalSelectedPlate = normalPlateState.minorGetSelectedPlate(collection, userName);

              if (normalSelectedPlate != null && normalSelectedPlate.id.isNotEmpty) {
                await normalPlateState.minorTogglePlateIsSelected(
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
                    const _ChatDashboardBar(),
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

class _ChatDashboardBar extends StatelessWidget {
  const _ChatDashboardBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          // ✅ 좌측: “채팅 열기” 버튼(말풍선 팝오버)
          const Expanded(
            child: ChatOpenButtonLite(),
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
  double _dragDistance = 0.0;

  double _vDragDistance = 0.0;
  bool _topOpening = false;

  static const double _hDistanceThreshold = 80.0;
  static const double _hVelocityThreshold = 1000.0;

  // ✅ 아래로 스와이프(TopSheet)만 유지
  static const double _vDistanceThresholdDown = 50.0;
  static const double _vVelocityThresholdDown = 700.0;

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    if (_dragDistance > _hDistanceThreshold && velocity > _hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const MinorInputPlateScreen(), fromLeft: true));
    } else if (_dragDistance < -_hDistanceThreshold && velocity < -_hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const SecondaryPage(), fromLeft: false));
    }
    _dragDistance = 0.0;
  }

  Future<void> _openParkingCompletedTableSheet(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    await showMinorParkingCompletedTableTopSheet(context);
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

  PageRouteBuilder _slidePage(Widget page, {required bool fromLeft}) {
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

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(context, details.primaryVelocity ?? 0),
      onVerticalDragStart: (_) => _vDragDistance = 0.0,
      onVerticalDragUpdate: (details) => _vDragDistance += details.delta.dy,
      onVerticalDragEnd: (details) => _handleVerticalDragEnd(context, details),
      child: Consumer2<MinorPageState, MinorPlateState>(
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

  Widget _buildCurrentPage(BuildContext context, MinorPageState state) {
    final pageInfo = state.pages[state.selectedIndex];
    return pageInfo.builder(context);
  }
}
