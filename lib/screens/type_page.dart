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

class TypePage extends StatelessWidget {
  const TypePage({super.key});

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
                await plateState.toggleIsSelected(
                  collection: collection,
                  plateNumber: selectedPlate.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
              }
            },
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 1,
                centerTitle: true,
                title: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios, size: 16, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      " version : Beta 0.8 ",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
              ),
              body: const RefreshableBody(),
              bottomNavigationBar: const PageBottomNavigation(),
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
      debugPrint('⏸ 드래그 거리(${_dragDistance.toStringAsFixed(1)}) 또는 속도($velocity) 부족 → 무시됨');
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
      onHorizontalDragUpdate: (details) {
        _dragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        _handleHorizontalDragEnd(context, details.primaryVelocity ?? 0);
      },
      child: Consumer<PageState>(
        builder: (context, state, child) {
          return Stack(
            children: [
              IndexedStack(
                index: state.selectedIndex,
                children: state.pages.map((pageInfo) => pageInfo.page).toList(),
              ),
              if (state.isLoading)
                Container(
                  color: Colors.black.withAlpha(51),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<PageState, PlateState, FieldSelectedDateState>(
      builder: (context, pageState, plateState, selectedDateState, child) {
        final selectedColor = AppColors.selectedItemColor;
        final unselectedColor = Colors.grey;

        final currentArea = context.read<AreaState>().currentArea;
        final plateRepository = context.read<PlateRepository>();

        return BottomNavigationBar(
          currentIndex: pageState.selectedIndex,
          onTap: pageState.onItemTapped,
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          items: List.generate(pageState.pages.length, (index) {
            final pageInfo = pageState.pages[index];
            final bool isSelected = pageState.selectedIndex == index;

            return BottomNavigationBarItem(
              icon: FutureBuilder<int>(
                future: plateRepository.getPlateCountByTypeAndArea(
                  pageInfo.collectionKey,
                  currentArea,
                ),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return _buildCountIcon(
                    count,
                    isSelected,
                    selectedColor,
                    unselectedColor,
                    pageInfo.title,
                  );
                },
              ),
              label: '',
            );
          }),
        );
      },
    );
  }

  Widget _buildCountIcon(
    int count,
    bool isSelected,
    Color selectedColor,
    Color unselectedColor,
    String label,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: TweenAnimationBuilder<Color?>(
              key: ValueKey(count),
              duration: const Duration(milliseconds: 300),
              tween: ColorTween(
                begin: Colors.redAccent,
                end: isSelected ? selectedColor : unselectedColor,
              ),
              builder: (context, color, child) {
                return Text(
                  '$count',
                  style: TextStyle(
                    fontSize: isSelected ? 26 : 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected ? selectedColor : unselectedColor,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
