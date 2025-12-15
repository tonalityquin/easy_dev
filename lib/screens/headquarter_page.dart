import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../states/page/hq_state.dart';
import '../states/page/page_info.dart';

// ✅ Dev Auth (시트는 더 이상 띄우지 않음)
import '../selector_hubs_package/dev_auth.dart';

// ✅ SecondaryPage (좌 스와이프 시 이동)
import 'secondary_page.dart';

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
            canPop: false,
            child: Scaffold(
              body: const RefreshableBody(),
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
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HqModeSwitchButton(),
          _BrandFooter(),
        ],
      );
    }

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

class RefreshableBody extends StatefulWidget {
  const RefreshableBody({super.key});

  @override
  State<RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<RefreshableBody> {
  // ── 가로 스와이프(우→좌: SecondaryPage 오픈)
  double _dragDistance = 0.0;
  bool _openingSecondary = false;

  static const double _hDistanceThreshold = 80.0;
  static const double _hVelocityThreshold = 1000.0;

  Future<bool> _isDevAuthorized() async {
    final restored = await DevAuth.restorePrefs(); // TTL 만료 처리 포함
    return restored.devAuthorized;
  }

  PageRouteBuilder _slidePage(Widget page, {required bool fromLeft}) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final begin = Offset(fromLeft ? -1.0 : 1.0, 0);
        final end = Offset.zero;
        final tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: Curves.easeInOut),
        );
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  Future<void> _openSecondaryIfAuthorized() async {
    if (_openingSecondary) return;
    _openingSecondary = true;

    try {
      final ok = await _isDevAuthorized();
      if (!mounted) return;

      // ✅ 요구사항: 개발자 인증이 아니면 “아무 반응 없음”
      if (!ok) return;

      Navigator.of(context).push(
        _slidePage(const SecondaryPage(), fromLeft: false),
      );
    } finally {
      _openingSecondary = false;
    }
  }

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    // 우→좌(좌 스와이프): dragDistance 음수, velocity 음수
    final fired =
        (_dragDistance < -_hDistanceThreshold) && (velocity < -_hVelocityThreshold);

    if (fired) {
      _openSecondaryIfAuthorized();
    }

    _dragDistance = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) =>
          _handleHorizontalDragEnd(context, details.primaryVelocity ?? 0.0),
      child: Consumer<HqState>(
        builder: (context, state, child) {
          final pages = state.pages;

          final safeIndex =
          pages.isEmpty ? 0 : state.selectedIndex.clamp(0, pages.length - 1);

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

        if (pages.length < 2) {
          return const SizedBox.shrink();
        }

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
