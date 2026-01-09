// lib/screens/lite_type_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/page/lite_page_state.dart';
import '../states/area/area_state.dart';
import '../states/plate/lite_plate_state.dart';
import '../states/user/user_state.dart';

import 'common_package/chat_package//lite_chat_bottom_sheet.dart';
import 'lite_mode/lite_input_package/lite_input_plate_screen.dart';
import 'lite_mode/lite_type_package/lite_common_widgets/dashboard_bottom_sheet/lite_home_dash_board_bottom_sheet.dart';
import 'lite_mode/lite_type_package/lite_common_widgets/reverse_sheet_package/lite_parking_completed_table_sheet.dart';
import 'secondary_page.dart';
import '../utils/snackbar_helper.dart';

import '../services/latest_message_service.dart';

// ✅ AppCardPalette ThemeExtension 사용
import '../theme.dart';

// ✅ Trace 기록용 Recorder
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class LiteTypePage extends StatefulWidget {
  const LiteTypePage({super.key});

  @override
  State<LiteTypePage> createState() => _LiteTypePageState();
}

class _LiteTypePageState extends State<LiteTypePage> {
  @override
  void initState() {
    super.initState();

    // ✅ Lite 진입: PlateState 절대 금지(구독 시작됨)
    // ✅ LitePlateState만 1회 로드(get) 수행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LitePlateState>().liteEnableForTypePages(withDefaults: true);
    });
  }

  @override
  void dispose() {
    // ✅ Lite 이탈: 로드/보류 상태 정리
    try {
      context.read<LitePlateState>().liteDisableAll();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LitePageState(),
      child: Builder(
        builder: (context) {
          final litePlateState = context.read<LitePlateState>();
          final pageState = context.read<LitePageState>();
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
              final liteSelectedPlate = litePlateState.liteGetSelectedPlate(collection, userName);

              if (liteSelectedPlate != null && liteSelectedPlate.id.isNotEmpty) {
                await litePlateState.togglePlateIsSelected(
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
                  builder: (_) => const LiteHomeDashBoardBottomSheet(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.liteBase,
                foregroundColor: palette.liteLight,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
                shadowColor: palette.liteDark.withOpacity(.25),
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

    return Consumer<LitePageState>(
      builder: (context, pageState, _) {
        return SizedBox(
          height: kBottomNavigationBarHeight,
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: () {
                // ✅ 홈 버튼 탭 Trace 기록
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
                  Icon(Icons.home, color: palette.liteBase),
                  const SizedBox(width: 8),
                  Text(
                    '홈',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: palette.liteBase,
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
      Navigator.of(context).push(_slidePage(const LiteInputPlateScreen(), fromLeft: true));
    } else if (_dragDistance < -_hDistanceThreshold && velocity < -_hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const SecondaryPage(), fromLeft: false));
    }
    _dragDistance = 0.0;
  }

  Future<void> _openParkingCompletedTableSheet(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    await showLiteParkingCompletedTableTopSheet(context);
  }

  Future<void> _handleVerticalDragEnd(BuildContext context, DragEndDetails details) async {
    final vy = details.primaryVelocity ?? 0.0;

    // ✅ (변경) 위로 스와이프하여 채팅 열기 로직 삭제
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
      child: Consumer2<LitePageState, LitePlateState>(
        builder: (context, pageState, litePlateState, _) {
          return Stack(
            children: [
              _buildCurrentPage(context, pageState),
              if (litePlateState.isLoading)
                Container(
                  color: Colors.white.withOpacity(.35),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(palette.liteBase),
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

  Widget _buildCurrentPage(BuildContext context, LitePageState state) {
    final pageInfo = state.pages[state.selectedIndex];
    return pageInfo.builder(context);
  }
}
