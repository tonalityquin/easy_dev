import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/plate/plate_state.dart';
import '../states/user/user_state.dart';
import '../utils/app_colors.dart';
import '../utils/snackbar_helper.dart';
import '../states/page/page_state.dart';
import '../states/page/page_info.dart';
import '../screens/input_pages/input_3_digit.dart';
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
          final userName = context
              .read<UserState>()
              .name;

          return WillPopScope(
            onWillPop: () async {
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
                return false;
              }

              return false;
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
                      " 번호 등록 | 업무 보조 ",
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

class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  void _handleDrag(BuildContext context, double velocity) {
    if (velocity > 0) {
      Navigator.of(context).push(_slidePage(const Input3Digit(), fromLeft: true));
    } else if (velocity < 0) {
      Navigator.of(context).push(_slidePage(const SecondaryPage(), fromLeft: false));
    } else {
      showFailedSnackbar(context, '드래그 동작이 감지되지 않았습니다.');
    }
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
      onHorizontalDragEnd: (details) {
        _handleDrag(context, details.primaryVelocity ?? 0);
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
                  color: Colors.black.withOpacity(0.2),
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
    return Consumer2<PageState, PlateState>(
      builder: (context, pageState, plateState, child) {
        final selectedColor = AppColors.selectedItemColor;
        final unselectedColor = Colors.grey;

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
            final int count = plateState
                .getPlatesByCollection(pageInfo.collectionKey)
                .length;
            final bool isSelected = pageState.selectedIndex == index;

            return BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ✅ 숫자 튐 + 색상 보간 강조
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
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
                      child: Text(pageInfo.title),
                    ),
                  ],
                ),
              ),
              label: '',
            );
          }),
        );
      },
    );
  }
}
