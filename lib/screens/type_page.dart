import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/plate/plate_repository.dart';
import '../states/page/page_state.dart';
import '../states/page/page_info.dart';
import '../states/area/area_state.dart';
import '../states/plate/plate_state.dart';
import '../states/user/user_state.dart';
import '../states/calendar/field_selected_date_state.dart';

import '../utils/app_colors.dart';

import '../screens/input_pages/input_plate_screen.dart';
import 'secondary_page.dart';

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
              bottomNavigationBar: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PageBottomNavigation(),
                  DebugTriggerBar(),
                ],
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

class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<PageState, FieldSelectedDateState>(
      builder: (context, pageState, selectedDateState, child) {
        final selectedColor = AppColors.selectedItemColor;
        final unselectedColor = Colors.grey;

        final currentArea = context.read<AreaState>().currentArea;
        final plateRepository = context.read<PlateRepository>();

        return BottomNavigationBar(
          currentIndex: pageState.selectedIndex,
          onTap: (index) {
            pageState.onItemTapped(
              context,
              index,
              onError: (msg) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg)),
                );
              },
            );
          },
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          // PageBottomNavigation 위젯 안 BottomNavigationBarItem 생성 부분
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

              // ✅ "홈" 탭 (카운팅 없음, 홈 아이콘 + 라벨)
              if (pageInfo.title == '홈') {
                return BottomNavigationBarItem(
                  icon: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.home, color: isSelected ? selectedColor : unselectedColor),
                      const SizedBox(height: 2),
                      Text('홈', style: labelStyle),
                    ],
                  ),
                  label: '',
                );
              }

              return BottomNavigationBarItem(
                icon: FutureBuilder<int>(
                  future: plateRepository.getPlateCountForTypePage(
                    pageInfo.collectionKey,
                    currentArea,
                  ),
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

class DebugTriggerBar extends StatelessWidget {
  const DebugTriggerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        color: Colors.transparent,
      ),
    );
  }
}
