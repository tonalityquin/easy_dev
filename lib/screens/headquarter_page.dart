import 'package:easydev/screens/secondary_page.dart';
import 'package:easydev/states/page/hq_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/page/page_info.dart';

class HeadquarterPage extends StatelessWidget {
  const HeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HqState(pages: hqPage)),
      ],
      child: Builder(
        builder: (context) {
          return PopScope(
            canPop: true,
            child: Scaffold(
              body: const RefreshableBody(),
              bottomNavigationBar: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PageBottomNavigation(),
                  DebugTriggerBar(), // ✅ 추가된 디버그 트리거 바
                ],
              ),
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
    if (velocity < 0) {
      Navigator.of(context).push(_slidePage(const SecondaryPage(), fromLeft: false));
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
      child: Consumer<HqState>(
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
    return Consumer<HqState>(
      builder: (context, state, child) {
        return BottomNavigationBar(
          currentIndex: state.selectedIndex,
          onTap: state.onItemTapped,
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: pageInfo.icon,
              label: pageInfo.title,
            );
          }).toList(),
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.purple,
          backgroundColor: Colors.white,
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
