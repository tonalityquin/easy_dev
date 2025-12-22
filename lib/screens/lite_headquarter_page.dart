// lib/screens/lite_headquarter_page.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../states/page/lite_hq_state.dart';
import '../states/page/lite_page_info.dart';

// ✅ Dev Auth (시트는 더 이상 띄우지 않음)
import '../selector_hubs_package/dev_auth.dart';

// ✅ SecondaryPage (좌 스와이프 시 이동)
import 'secondary_page.dart';

// ✅ AppCardPalette ThemeExtension 사용
import '../theme.dart';

class LiteHeadquarterPage extends StatelessWidget {
  const LiteHeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LiteHqState(pages: liteHqPage)),
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
    final state = context.watch<LiteHqState>();
    final pages = state.pages;

    if (pages.length < 2) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiteHqModeSwitchButton(),
          _BrandFooter(),
        ],
      );
    }

    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LiteHqModeSwitchButton(),
        PageBottomNavigation(),
        _BrandFooter(),
      ],
    );
  }
}

class _LiteHqModeSwitchButton extends StatelessWidget {
  const _LiteHqModeSwitchButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('서비스 본사로 전환'),
          style: _switchBtnStyle(context),
          onPressed: () {
            _replaceWithAnimatedRoute(
              context,
              AppRoutes.headquarterPage,
              beginOffset: const Offset(-1.0, 0.0),
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
    final fired =
        (_dragDistance < -_hDistanceThreshold) && (velocity < -_hVelocityThreshold);

    if (fired) {
      _openSecondaryIfAuthorized();
    }

    _dragDistance = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) =>
          _handleHorizontalDragEnd(context, details.primaryVelocity ?? 0.0),
      child: Consumer<LiteHqState>(
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
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          palette.liteBase,
                        ),
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
    final palette = AppCardPalette.of(context);

    return Consumer<LiteHqState>(
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
          selectedItemColor: palette.liteBase,
          unselectedItemColor: palette.liteDark.withOpacity(.55),
          backgroundColor: Colors.white,
          elevation: 0,
          showUnselectedLabels: true,
        );
      },
    );
  }
}

ButtonStyle _switchBtnStyle(BuildContext context) {
  // 기존 구현은 “흰색 바탕 + 검정 글자 + 회색 보더”였으므로
  // 팔레트 적용은 보더/아이콘 정도만 가볍게 반영하고, UX는 유지합니다.
  final palette = AppCardPalette.of(context);

  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: palette.liteDark, // 기존 black → liteDark로 통일
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: BorderSide(
      color: palette.liteLight.withOpacity(.8), // 기존 grey → liteLight 톤
      width: 1.0,
    ),
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
