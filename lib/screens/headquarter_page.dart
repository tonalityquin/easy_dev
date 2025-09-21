// lib/screens/headquarter_page.dart
import 'package:easydev/screens/secondary_page.dart';
import 'package:easydev/states/page/hq_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../states/page/page_info.dart';
import 'head_package/shared/hq_switch_fab.dart';

/// Headquarter 전용 팔레트
class _HqPalette {
  static const base = Color(0xFF1E88E5); // #1E88E5
  static const dark = Color(0xFF1565C0); // #1565C0
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
            // ✅ 이 화면에서만 뒤로가기(pop) 차단 → 앱 종료 방지
            canPop: false,
            child: Scaffold(
              body: const RefreshableBody(),
              // ✅ 하단 영역: 탭이 2개 이상이면 BottomNavigationBar + 브랜드 푸터,
              //    1개 이하이면 브랜드 푸터만 노출
              bottomNavigationBar: const SafeArea(
                top: false,
                child: _BottomArea(),
              ),
              // ✅ 두 페이지에서 동일 위치(endFloat)에 노출되는 상호 이동 FAB
              floatingActionButton: HqSwitchFab(
                label: '본사 허브',
                icon: Icons.dashboard_customize_rounded,
                onPressed: () => Navigator.of(context)
                    .pushReplacementNamed(AppRoutes.headStub),
              ),
              floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            ),
          );
        },
      ),
    );
  }
}

class _BottomArea extends StatelessWidget {
  const _BottomArea();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HqState>();
    final pages = state.pages;

    const footer = _BrandFooter();

    if (pages.length < 2) {
      // ✅ 탭이 1개 이하면 BottomNavigationBar를 만들지 않음(Assert 회피)
      return footer;
    }

    // ✅ 탭이 2개 이상일 때만 하단 네비게이션 + 푸터
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        PageBottomNavigation(),
        _BrandFooter(),
      ],
    );
  }
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 48,
        child: Semantics(
          label: 'Pelican 브랜드 로고',
          image: true,
          child: Image.asset('assets/images/pelican.png'),
        ),
      ),
    );
  }
}

class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  static const _kSwipeVelocityThreshold = 300; // px/s

  void _handleDrag(BuildContext context, double velocity) {
    // 왼쪽으로 스와이프(velocity < -threshold) 시 보조 페이지로 전환
    if (velocity < -_kSwipeVelocityThreshold) {
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
          final pages = state.pages;

          // ✅ 안전 인덱스(범위 클램프) — int 캐스팅
          final safeIndex = pages.isEmpty
              ? 0
              : state.selectedIndex.clamp(0, pages.length - 1);

          // ✅ children이 비어 있으면 IndexedStack이 깨지므로 최소 1개는 유지
          final children = pages.isEmpty
              ? const <Widget>[SizedBox.shrink()]
              : pages.map((p) => p.page).toList();

          return Stack(
            children: [
              IndexedStack(
                index: safeIndex,
                children: children,
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
        final pages = state.pages;

        // ✅ 방어적 가드: 2개 미만이면 아무것도 렌더링하지 않음(Assert 예방)
        if (pages.length < 2) {
          return const SizedBox.shrink();
        }

        // ✅ 안전 인덱스 적용 — int 캐스팅
        final currentIndex = state.selectedIndex.clamp(0, pages.length - 1);

        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentIndex,
          onTap: state.onItemTapped,
          items: pages
              .map(
                (pageInfo) => BottomNavigationBarItem(
              icon: pageInfo.icon,
              label: pageInfo.title,
            ),
          )
              .toList(),
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
