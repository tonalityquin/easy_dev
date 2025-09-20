// lib/screens/type_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../enums/plate_type.dart';
import '../repositories/plate_repo_services/plate_repository.dart';
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

// ⬇️ 추가: 최근 메시지 저장/재생 기능
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts/tts_manager.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const fg = Color(0xFFFFFFFF);   // 전경(흰색)
}

class TypePage extends StatefulWidget {
  const TypePage({super.key});

  @override
  State<TypePage> createState() => _TypePageState();
}

class _TypePageState extends State<TypePage> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PageState(pages: defaultPages),
      child: Builder(
        builder: (context) {
          final plateState = context.read<PlateState>();
          final pageState = context.read<PageState>();
          final userName = context.read<UserState>().name;

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

  static String _prefsKey(String area) => 'chat.latest_message.$area';

  static Future<void> _saveLatestToPrefs(String area, String message) async {
    if (area.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey(area), message);
    } catch (e) {
      debugPrint('⚠️ save latest message failed: $e');
    }
  }

  static Future<String?> _readLatestFromPrefs(String area) async {
    if (area.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey(area));
    } catch (e) {
      debugPrint('⚠️ read latest message failed: $e');
      return null;
    }
  }

  static Future<void> _replayLatestTts(BuildContext context, String area) async {
    final text = (await _readLatestFromPrefs(area))?.trim() ?? '';
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
          // ── 채팅: 최근 메시지 저장 + "다시 듣기" 버튼
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
                : StreamBuilder<String>(
              // 최신 메시지를 스트림으로 받되, 화면에는 “다시 듣기”만 보임
              stream: latestMessageStream(area),
              builder: (context, snapshot) {
                final latest = (snapshot.data ?? '').trim();
                if (latest.isNotEmpty) {
                  // 비동기 저장(중복 호출 무방)
                  _saveLatestToPrefs(area, latest);
                }

                return ElevatedButton(
                  onPressed: () => _replayLatestTts(context, area),
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

  // ── 세로 스와이프(아래→위: 채팅 바텀시트)
  double _vDragDistance = 0.0;
  double? _vStartDy;
  bool _chatOpening = false; // 중복 오픈 방지

  // 임계값
  static const double _hDistanceThreshold = 80.0;
  static const double _hVelocityThreshold = 1000.0;

  static const double _vDistanceThreshold = 80.0;
  static const double _vVelocityThreshold = 1000.0;

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

  Future<void> _handleVerticalDragEnd(BuildContext context, DragEndDetails details) async {
    final vy = details.primaryVelocity ?? 0.0; // 위로 스와이프는 음수

    // 화면 어디서든 위로 빠르게 스와이프하면 실행
    final fired = _vDragDistance < -_vDistanceThreshold && vy < -_vVelocityThreshold;

    if (fired && !_chatOpening) {
      _chatOpening = true;
      debugPrint(
        '✅[V] 채팅 오픈 트리거: startDy=${_vStartDy?.toStringAsFixed(1)}, '
            '거리(${_vDragDistance.toStringAsFixed(1)}), 속도($vy)',
      );
      // iOS 제스처 충돌 방지용 아주 짧은 디바운스
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (mounted) chatBottomSheet(context);
      _chatOpening = false;
    } else {
      debugPrint('⏸[V] 거리(${_vDragDistance.toStringAsFixed(1)}), 속도($vy) → 조건 미충족(무시)');
    }

    _vDragDistance = 0.0;
    _vStartDy = null;
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

      // ── 세로 스와이프(아래→위: 채팅)
      onVerticalDragStart: (details) {
        _vStartDy = details.globalPosition.dy;
        _vDragDistance = 0.0; // 시작 시 리셋
      },
      onVerticalDragUpdate: (details) => _vDragDistance += details.delta.dy, // 위로 음수 누적
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
  String? _area; // 현재 area 캐시
  final Map<PlateType, Future<int>> _countFutures = {};

  void _ensureFuturesForCurrentAreaAndPages() {
    final areaNow = context.read<AreaState>().currentArea.trim();
    final repo = context.read<PlateRepository>();
    final pages = context.read<PageState>().pages;

    final desiredTypes = <PlateType>{
      for (final p in pages)
        if (p.title != '홈') p.collectionKey,
    };

    final areaChanged = _area != areaNow;
    if (areaChanged) {
      _area = areaNow;
      _countFutures.clear();
    }

    final removeKeys = _countFutures.keys.where((k) => !desiredTypes.contains(k)).toList();
    for (final k in removeKeys) {
      _countFutures.remove(k);
    }

    for (final type in desiredTypes) {
      _countFutures.putIfAbsent(type, () => repo.getPlateCountForTypePage(type, _area!));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureFuturesForCurrentAreaAndPages();
  }

  @override
  Widget build(BuildContext context) {
    _ensureFuturesForCurrentAreaAndPages();

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
              final future = _countFutures[type];

              return BottomNavigationBarItem(
                icon: FutureBuilder<int>(
                  future: future,
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;

                    // ✅ 입차/출차 숫자 색 기존값으로 복원 (비선택 시)
                    final bool isIn = pageInfo.title == '입차 요청';
                    final bool isOut = pageInfo.title == '출차 요청';
                    Color countColor;
                    if (isIn || isOut) {
                      countColor = isSelected
                          ? selectedColor
                          : (isIn ? Colors.redAccent : Colors.indigoAccent);
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
