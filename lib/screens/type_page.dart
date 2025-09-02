import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../enums/plate_type.dart';
import '../repositories/plate/plate_repository.dart';
import '../states/calendar/field_calendar_state.dart';
import '../states/page/page_state.dart';
import '../states/page/page_info.dart';
import '../states/area/area_state.dart';
import '../states/plate/plate_state.dart';
import '../states/user/user_state.dart';

import '../utils/app_colors.dart';

import '../screens/input_pages/input_plate_screen.dart';
import '../screens/type_pages/commons/dashboard_bottom_sheet/dash_board_bottom_sheet.dart';
import 'type_pages/commons/chats/chat_bottom_sheet.dart';
import 'secondary_page.dart';
import '../utils/snackbar_helper.dart';

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
            canPop: true,
            onPopInvoked: (didPop) async {
              if (!didPop) return;

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
            },
            child: Scaffold(
              body: const RefreshableBody(),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: StreamBuilder<String>(
                              stream: latestMessageStream(
                                context.read<AreaState>().currentArea.trim(),
                              ),
                              builder: (context, snapshot) {
                                final latestMessage = snapshot.data ?? '채팅 열기';

                                return ElevatedButton(
                                  onPressed: () {
                                    chatBottomSheet(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.message, color: Colors.black, size: 20),
                                      const SizedBox(width: 6),
                                      Text(
                                        latestMessage.length > 20
                                            ? '${latestMessage.substring(0, 20)}...'
                                            : latestMessage,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.black),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const DashBoardBottomSheet(),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black87,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    ),
                    const PageBottomNavigation(),
                    // Pelican 이미지 행 (그늘 방지용 흰 배경 + 안전 영역 여백)
                    Builder(
                      builder: (context) {
                        final bottomInset = MediaQuery.of(context).padding.bottom;
                        return Container(
                          color: Colors.white,
                          padding: EdgeInsets.only(top: 8, bottom: bottomInset + 8),
                          alignment: Alignment.center,
                          child: SizedBox(
                            height: 80,
                            child: Image.asset('assets/images/pelican.png'),
                          ),
                        );
                      },
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

class RefreshableBody extends StatefulWidget {
  const RefreshableBody({super.key});

  @override
  State<RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<RefreshableBody> {
  double _dragDistance = 0.0;

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    const velocityThreshold = 1000.0;
    const distanceThreshold = 80.0;

    if (_dragDistance > distanceThreshold && velocity > velocityThreshold) {
      Navigator.of(context).push(_slidePage(const InputPlateScreen(), fromLeft: true));
    } else if (_dragDistance < -distanceThreshold && velocity < -velocityThreshold) {
      Navigator.of(context).push(_slidePage(const SecondaryPage(), fromLeft: false));
    } else {
      debugPrint(
        '⏸ 드래그 거리(${_dragDistance.toStringAsFixed(1)}) 또는 속도($velocity) 부족 → 무시됨',
      );
    }

    _dragDistance = 0.0;
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
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(
        context,
        details.primaryVelocity ?? 0,
      ),
      child: Consumer<PageState>(
        builder: (context, state, child) {
          return Stack(
            children: [
              _buildCurrentPage(context, state.selectedIndex),
              if (state.isLoading)
                Container(
                  color: Colors.black.withAlpha(51),
                  child: const Center(child: CircularProgressIndicator()),
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

/// 하단 네비게이션: (type, area)별 Future<int> 캐싱으로 중복 쿼리 방지
class PageBottomNavigation extends StatefulWidget {
  const PageBottomNavigation({super.key});

  @override
  State<PageBottomNavigation> createState() => _PageBottomNavigationState();
}

class _PageBottomNavigationState extends State<PageBottomNavigation> {
  String? _area; // 현재 area 캐시
  // ✅ PlateType으로 명시: Object 금지
  final Map<PlateType, Future<int>> _countFutures = {};

  void _ensureFuturesForCurrentAreaAndPages() {
    final areaNow = context.read<AreaState>().currentArea.trim();
    final repo = context.read<PlateRepository>();
    final pages = context.read<PageState>().pages;

    // ✅ 홈 제외한 탭들의 type 집합을 PlateType으로 명시
    final desiredTypes = <PlateType>{
      for (final p in pages)
        if (p.title != '홈') p.collectionKey, // collectionKey가 PlateType
    };

    // area가 바뀌면 캐시 무효화
    final areaChanged = _area != areaNow;
    if (areaChanged) {
      _area = areaNow;
      _countFutures.clear();
    }

    // 페이지에서 사라진 타입의 캐시 제거
    final removeKeys = _countFutures.keys.where((k) => !desiredTypes.contains(k)).toList();
    for (final k in removeKeys) {
      _countFutures.remove(k);
    }

    // 필요한 타입의 Future 생성(없으면 생성, 있으면 재사용)
    for (final type in desiredTypes) {
      _countFutures.putIfAbsent(type, () {
        // 반드시 _area가 세팅된 이후 호출됨(didChangeDependencies/build에서 보장)
        return repo.getPlateCountForTypePage(type, _area!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureFuturesForCurrentAreaAndPages();
  }

  @override
  Widget build(BuildContext context) {
    // 상위 상태 변화로 build가 잦더라도 동일 Future 재사용 보장
    _ensureFuturesForCurrentAreaAndPages();

    return Consumer2<PageState, FieldSelectedDateState>(
      builder: (context, pageState, selectedDateState, child) {
        final selectedColor = AppColors.selectedItemColor;
        final unselectedColor = Colors.grey;

        return BottomNavigationBar(
          elevation: 0,
          // 그림자 제거로 하단 이미지 그늘 방지
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

              // ✅ (type, area) 조합의 동일 Future 재사용
              final PlateType type = pageInfo.collectionKey; // 타입 명시
              final future = _countFutures[type]; // _ensure에서 putIfAbsent 완료

              return BottomNavigationBarItem(
                icon: FutureBuilder<int>(
                  future: future,
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: isSelected ? 22 : 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? selectedColor : Colors.redAccent,
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
