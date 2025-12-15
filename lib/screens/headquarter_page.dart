import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../states/page/hq_state.dart';
import '../states/page/page_info.dart';

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

    if (pages.length < 2) {
      // ✅ 탭이 1개 이하면 BottomNavigationBar를 만들지 않음(Assert 회피)
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HqModeSwitchButton(),
          _BrandFooter(),
        ],
      );
    }

    // ✅ 탭이 2개 이상일 때만 하단 네비게이션 + 푸터
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HqModeSwitchButton(),
        PageBottomNavigation(),
        _BrandFooter(),
      ],
    );
  }
}

class _HqModeSwitchButton extends StatelessWidget {
  const _HqModeSwitchButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Lite 본사로 전환'),
          style: _switchBtnStyle(),
          onPressed: () {
            _replaceWithAnimatedRoute(
              context,
              AppRoutes.liteHeadquarterPage,
              // 서비스 → Lite: 오른쪽에서 들어오는 방향
              beginOffset: const Offset(1.0, 0.0),
            );
          },
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Consumer<HqState>(
      builder: (context, state, child) {
        final pages = state.pages;

        // ✅ 안전 인덱스(범위 클램프)
        final safeIndex =
        pages.isEmpty ? 0 : state.selectedIndex.clamp(0, pages.length - 1);

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
                      valueColor:
                      AlwaysStoppedAnimation<Color>(_HqPalette.base),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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

        // ✅ 안전 인덱스 적용
        final currentIndex =
        state.selectedIndex.clamp(0, pages.length - 1);

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

/// ✅ 전환 버튼 디자인(요청하신 _layerToggleBtnStyle 디자인 반영)
ButtonStyle _switchBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

/// ✅ named route를 유지하면서도, 전환 시 애니메이션을 강제하기 위한 pushReplacement(PageRouteBuilder)
void _replaceWithAnimatedRoute(
    BuildContext context,
    String routeName, {
      required Offset beginOffset,
    }) {
  final builder = appRoutes[routeName];
  if (builder == null) return;

  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      settings: RouteSettings(name: routeName),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return builder(ctx);
      },
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        final slide = Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(curved);

        final fade = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        );

        return SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: fade,
            child: child,
          ),
        );
      },
    ),
  );
}
