import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/plate/plate_state.dart';
import '../states/user/user_state.dart';
import '../utils/app_colors.dart';
import '../utils/show_snackbar.dart';
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
          final userName = context.read<UserState>().name;

          return WillPopScope(
            onWillPop: () async {
              // 현재 선택된 collection 가져오기
              final currentPage = pageState.pages[pageState.selectedIndex];
              final collection = currentPage.collectionKey;

              // 선택된 plate 있는지 확인
              final selectedPlate = plateState.getSelectedPlate(collection, userName);
              if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
                await plateState.toggleIsSelected(
                  collection: collection,
                  plateNumber: selectedPlate.plateNumber,
                  userName: userName,
                  onError: (msg) => debugPrint(msg),
                );
                return false; // plate 해제만 하고 뒤로가기 차단
              }

              return false; // 선택 없을 경우에도 앱 종료 방지
            },
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: AppColors.selectedItemColor,
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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const Input3Digit()),
      );
    } else if (velocity < 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SecondaryPage()),
      );
    } else {
      showSnackbar(context, '드래그 동작이 감지되지 않았습니다.');
    }
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
                const Center(
                  child: CircularProgressIndicator(),
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
        return BottomNavigationBar(
          currentIndex: pageState.selectedIndex,
          onTap: pageState.onItemTapped,
          items: List.generate(pageState.pages.length, (index) {
            final pageInfo = pageState.pages[index];
            final int count = plateState.getPlatesByCollection(pageInfo.collectionKey).length;
            final bool isSelected = pageState.selectedIndex == index;

            final textColor = isSelected ? Colors.red : Colors.black;
            final countColor = isSelected ? Colors.green : Colors.black;
            final countSize = isSelected ? 26.0 : 20.0;

            return BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: countSize,
                        fontWeight: FontWeight.bold,
                        color: countColor,
                      ),
                      child: Text('$count'),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      child: Text(pageInfo.title),
                    ),
                  ],
                ),
              ),
              label: '',
            );
          }),
          backgroundColor: Colors.white,
        );
      },
    );
  }
}
