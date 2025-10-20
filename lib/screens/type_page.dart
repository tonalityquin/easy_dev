// lib/screens/type_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../enums/plate_type.dart';

// 🔁 리팩터링: 카운트 조회에 Repository가 더 이상 필요하지 않으므로 제거
// import '../repositories/plate_repo_services/plate_repository.dart';
import '../states/calendar/field_calendar_state.dart';
import '../states/page/page_state.dart';
import '../states/page/page_info.dart';
import '../states/area/area_state.dart';
import '../states/plate/plate_state.dart';
import '../states/user/user_state.dart';

import '../screens/input_package/input_plate_screen.dart';
import '../screens/type_package/common_widgets/dashboard_bottom_sheet/home_dash_board_bottom_sheet.dart';
import 'type_package/common_widgets/chats/chat_bottom_sheet.dart';
import 'secondary_page.dart';
import '../utils/snackbar_helper.dart';

import '../utils/tts/tts_manager.dart';

// ⬇️ 추가: 전역 최신 메시지 서비스(실시간 구독 + 캐시)
import '../services/latest_message_service.dart';

// ⬇️ 추가: 역 바텀시트(Top Sheet)
import 'type_package/parking_completed_package/reverse_sheet/reverse_page_top_sheet.dart';
import 'type_package/parking_completed_package/reverse_sheet/parking_completed_reverse_page.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const fg = Color(0xFFFFFFFF); // 전경(흰색)
}

class TypePage extends StatefulWidget {
  const TypePage({super.key});

  @override
  State<TypePage> createState() => _TypePageState();
}

class _TypePageState extends State<TypePage> {
  @override
  void initState() {
    super.initState();
    // ✅ 필드 페이지 진입: PlateState 활성화만 (즉시 재구독 호출 제거)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final plateState = context.read<PlateState>();
      plateState.enableForTypePages();
      // ❌ plateState.syncWithAreaState(); // 초기 진입 직후 재구독 제거
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PageState(pages: defaultPages),
      child: Builder(
        builder: (context) {
          final plateState = context.read<PlateState>();
          final pageState = context.read<PageState>();
          final userName = context.read<UserState>().name;

          // ★ 현재 area 기반으로 전역 리스너(실시간 READ) 시작 — idempotent
          final currentArea = context.read<AreaState>().currentArea.trim();
          if (currentArea.isNotEmpty) {
            LatestMessageService.instance.start(currentArea);
          }

          return PopScope(
            // ✅ 이 화면에서만 뒤로가기(pop) 차단 → 앱 종료 방지
            canPop: false,
            // 뒤로가기를 시도했지만 팝이 막힌 경우(didPop=false)에만 선택 해제 로직 수행
            onPopInvoked: (didPop) async {
              if (didPop) return; // 실제로 팝된 경우는 없음(canPop:false)

              final currentPage = pageState.pages[pageState.selectedIndex];
              final collection = currentPage.collectionKey;
              final selectedPlate = plateState.getSelectedPlate(collection, userName);

              if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
                await plateState.togglePlateIsSelected(
                  collection: collection,
                  plateNumber: selectedPlate.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
              }
              // ☆ 여기서 스낵바 안내는 하지 않음(요청사항)
            },
            child: Scaffold(
              body: const RefreshableBody(),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _ChatDashboardBar(),
                    const PageBottomNavigation(),
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

  static Future<void> _replayLatestTts(BuildContext context, String area) async {
    // ★ Firestore 접근 없음: 서비스가 저장해 둔 로컬 캐시만 사용 → READ 0
    final text = (await LatestMessageService.instance.readFromPrefs()).trim();
    if (text.isEmpty) {
      showSelectedSnackbar(context, '최근 메시지가 없습니다.');
      return;
    }
    await TtsManager.speak(
      text,
      language: 'ko-KR',
      rate: 0.4,
      volume: 1.0,
      pitch: 1.0,
      preferGoogleOnAndroid: true,
      openPlayStoreIfMissing: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = context.read<AreaState>().currentArea.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          // ── 채팅: 최근 메시지 표시 + "다시 듣기" (Firestore 구독 없음)
          Expanded(
            child: area.isEmpty
                ? ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _Palette.dark.withOpacity(.35),
                disabledBackgroundColor: Colors.white,
                disabledForegroundColor: _Palette.dark.withOpacity(.35),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volume_up, size: 20),
                  SizedBox(width: 6),
                  Text('다시 듣기'),
                ],
              ),
            )
                : ValueListenableBuilder<LatestMessageData>(
              // ★ 전역 서비스의 메모리 캐시를 구독 → Firestore 접근 없음
              valueListenable: LatestMessageService.instance.latest,
              builder: (context, latestData, _) {
                final hasText = latestData.text.trim().isNotEmpty;
                return ElevatedButton(
                  onPressed: hasText ? () => _replayLatestTts(context, area) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _Palette.base,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volume_up, size: 20),
                      SizedBox(width: 6),
                      Text('다시 듣기', overflow: TextOverflow.ellipsis),
                    ],
                  ),
                );
              },
            ),
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
                  builder: (_) => const HomeDashBoardBottomSheet(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _Palette.base,
                foregroundColor: _Palette.fg,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
                shadowColor: _Palette.dark.withOpacity(.25),
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

class RefreshableBody extends StatefulWidget {
  const RefreshableBody({super.key});

  @override
  State<RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<RefreshableBody> {
  // ── 가로 스와이프(좌/우 페이지 전환)
  double _dragDistance = 0.0;

  // ── 세로 스와이프
  //   - 아래→위: 채팅 바텀시트
  //   - 위→아래: 역 바텀시트(Top Sheet)
  double _vDragDistance = 0.0;
  bool _chatOpening = false; // 중복 오픈 방지(채팅)
  bool _topOpening = false; // 중복 오픈 방지(역 바텀시트)

  // 임계값
  static const double _hDistanceThreshold = 80.0;
  static const double _hVelocityThreshold = 1000.0;

  // ⬇️ 민감도 상향(더 널널)
  static const double _vDistanceThresholdUp = 70.0;
  static const double _vVelocityThresholdUp = 900.0;
  static const double _vDistanceThresholdDown = 50.0;
  static const double _vVelocityThresholdDown = 700.0;

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    if (_dragDistance > _hDistanceThreshold && velocity > _hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const InputPlateScreen(), fromLeft: true));
    } else if (_dragDistance < -_hDistanceThreshold && velocity < -_hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const SecondaryPage(), fromLeft: false));
    } else {
      debugPrint('⏸[H] 거리(${_dragDistance.toStringAsFixed(1)})/속도($velocity) 부족 → 무시');
    }
    _dragDistance = 0.0;
  }

  Future<void> _openReverseTopSheet(BuildContext context) async {
    // iOS 제스처 충돌 방지용 아주 짧은 디바운스
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;

    await showReversePageTopSheet(
      context: context,
      maxHeightFactor: 0.92,
      builder: (_) => const ParkingCompletedReversePage(),
    );
  }

  Future<void> _handleVerticalDragEnd(BuildContext context, DragEndDetails details) async {
    final vy = details.primaryVelocity ?? 0.0; // 위로 스와이프는 음수, 아래로는 양수

    // 위로 빠르게 스와이프 → 채팅 (둘 중 하나만 만족해도 트리거)
    final firedUp = (_vDragDistance < -_vDistanceThresholdUp) || (vy < -_vVelocityThresholdUp);
    // 아래로 빠르게 스와이프 → 역 바텀시트 (둘 중 하나만 만족해도 트리거)
    final firedDown = (_vDragDistance > _vDistanceThresholdDown) || (vy > _vVelocityThresholdDown);

    if (firedUp && !_chatOpening) {
      _chatOpening = true;
      debugPrint('✅[V-UP] 채팅 오픈: 거리=${_vDragDistance.toStringAsFixed(1)} / 속도=$vy '
          '(need dist<-${_vDistanceThresholdUp} OR vy<-${_vVelocityThresholdUp})');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (mounted) chatBottomSheet(context);
      _chatOpening = false;
    } else if (firedDown && !_topOpening) {
      _topOpening = true;
      debugPrint('✅[V-DOWN] 역 바텀시트 오픈: 거리=${_vDragDistance.toStringAsFixed(1)} / 속도=$vy '
          '(need dist>${_vDistanceThresholdDown} OR vy>${_vVelocityThresholdDown})');
      await _openReverseTopSheet(context);
      _topOpening = false;
    } else {
      debugPrint('⏸[V] 거리=${_vDragDistance.toStringAsFixed(1)}, 속도=$vy → 조건 미충족(무시)');
    }

    _vDragDistance = 0.0; // reset
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,

      // ── 가로 스와이프(좌/우 페이지 전환)
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(
        context,
        details.primaryVelocity ?? 0,
      ),

      // ── 세로 스와이프(아래→위: 채팅 / 위→아래: 역 바텀시트)
      onVerticalDragStart: (_) {
        _vDragDistance = 0.0; // 시작 시 리셋
      },
      onVerticalDragUpdate: (details) => _vDragDistance += details.delta.dy, // 위로 음수, 아래로 양수
      onVerticalDragEnd: (details) => _handleVerticalDragEnd(context, details),

      child: Consumer<PageState>(
        builder: (context, state, child) {
          return Stack(
            children: [
              _buildCurrentPage(context, state.selectedIndex),
              if (state.isLoading)
                Container(
                  color: Colors.white.withOpacity(.35),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(_Palette.base),
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

  Widget _buildCurrentPage(BuildContext context, int index) {
    if (index == 0) {
      return defaultPages[0].builder(context);
    } else {
      return IndexedStack(
        index: index - 1,
        children: defaultPages.sublist(1).map((pageInfo) => pageInfo.builder(context)).toList(),
      );
    }
  }
}

class PageBottomNavigation extends StatefulWidget {
  const PageBottomNavigation({super.key});

  @override
  State<PageBottomNavigation> createState() => _PageBottomNavigationState();
}

class _PageBottomNavigationState extends State<PageBottomNavigation> {
  // 🔁 리팩터링: 단발 카운트 Future 캐시 제거
  // String? _area;
  // final Map<PlateType, Future<int>> _countFutures = {};
  // void _ensureFuturesForCurrentAreaAndPages() { ... }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 🔁 리팩터링: 더 이상 준비할 Future가 없으므로 호출 제거
    // _ensureFuturesForCurrentAreaAndPages();
  }

  @override
  Widget build(BuildContext context) {
    // 🔁 리팩터링: Future 준비 로직 제거
    // _ensureFuturesForCurrentAreaAndPages();

    // 팔레트 기반 선택/비선택 색
    final selectedColor = _Palette.base;
    final unselectedColor = _Palette.dark.withOpacity(.55);

    return Consumer2<PageState, FieldSelectedDateState>(
      builder: (context, pageState, selectedDateState, child) {
        return BottomNavigationBar(
          elevation: 0,
          currentIndex: pageState.selectedIndex,
          onTap: (index) {
            pageState.onItemTapped(
              context,
              index,
              onError: (msg) => showFailedSnackbar(context, msg),
            );
          },
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          items: List.generate(
            pageState.pages.length,
                (index) {
              final pageInfo = pageState.pages[index];
              final isSelected = pageState.selectedIndex == index;

              final labelStyle = TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? selectedColor : unselectedColor,
              );

              if (pageInfo.title == '홈') {
                return BottomNavigationBarItem(
                  icon: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.home,
                        size: isSelected ? 32 : 28,
                        color: isSelected ? selectedColor : unselectedColor,
                      ),
                      const SizedBox(height: 2),
                      Text('홈', style: labelStyle),
                    ],
                  ),
                  label: '',
                );
              }

              final PlateType type = pageInfo.collectionKey;

              // 🔁 리팩터링 핵심:
              //   - FutureBuilder<int> → Selector<PlateState, int>
              //   - PlateState의 실시간 목록 길이로 카운트 표시
              return BottomNavigationBarItem(
                icon: Selector<PlateState, int>(
                  selector: (_, s) => s.dataOfType(type).length,
                  builder: (context, count, _) {
                    // ✅ 입차/출차 숫자 색 기존값으로 복원 (비선택 시)
                    final bool isIn = pageInfo.title == '입차 요청';
                    final bool isOut = pageInfo.title == '출차 요청';
                    Color countColor;
                    if (isIn || isOut) {
                      countColor = isSelected ? selectedColor : (isIn ? Colors.redAccent : Colors.indigoAccent);
                    } else {
                      countColor = isSelected ? selectedColor : _Palette.dark.withOpacity(.75);
                    }

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: isSelected ? 22 : 18,
                            fontWeight: FontWeight.bold,
                            color: countColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(pageInfo.title, style: labelStyle),
                      ],
                    );
                  },
                ),
                label: '',
              );
            },
          ),
        );
      },
    );
  }
}
