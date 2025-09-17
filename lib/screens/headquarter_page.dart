import 'package:easydev/screens/secondary_page.dart';
import 'package:easydev/states/page/hq_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/page/page_info.dart';

/// Headquarter 전용 팔레트
class _HqPalette {
  static const base = Color(0xFF1E88E5);  // #1E88E5
  static const dark = Color(0xFF1565C0);  // #1565C0
}

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
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PageBottomNavigation(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 48,
                        child: Image.asset('assets/images/pelican.png'),
                      ),
                    ),
                  ),
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
                  color: Colors.white.withOpacity(.35),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(_HqPalette.base),
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
}

class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HqState>(
      builder: (context, state, child) {
        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: state.selectedIndex,
          onTap: state.onItemTapped,
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: pageInfo.icon,
              label: pageInfo.title,
            );
          }).toList(),
          selectedItemColor: _HqPalette.base,
          unselectedItemColor: _HqPalette.dark.withOpacity(.55),
          backgroundColor: Colors.white,
          elevation: 0,
          showUnselectedLabels: true,
        );
      },
    );
  }
}
