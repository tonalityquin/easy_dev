import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/page/application/minor/minor_page_info.dart';
import '../../../../shared/plate/application/minor/minor_plate_state.dart';
import '../../../../shared/secondary/pages/secondary_page.dart';
import '../../../selector/application/dev_auth.dart';
import '../../applications/minor/minor_hq_state.dart';
import '../../widgets/headquarter_mode_switch_button.dart';

class MinorHeadquarterPage extends StatelessWidget {
  const MinorHeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MinorHqState(pages: minorHqPage)),
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
    final state = context.watch<MinorHqState>();
    final pages = state.pages;
    final switchButton = HeadquarterModeSwitchButton(
      currentModeKey: 'minor',
      currentScreen: 'minor_headquarter_page',
      onBeforeSwitch: () => context.read<MinorPlateState>().minorDisableAll(),
    );

    if (pages.length < 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [switchButton],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PageBottomNavigation(),
        switchButton,
      ],
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
    final restored = await DevAuth.restorePrefs();
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
      if (!ok) return;

      Navigator.of(context).push(
        _slidePage(const SecondaryPage(), fromLeft: false),
      );
    } finally {
      _openingSecondary = false;
    }
  }

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    final fired = (_dragDistance < -_hDistanceThreshold) && (velocity < -_hVelocityThreshold);

    if (fired) {
      _openSecondaryIfAuthorized();
    }

    _dragDistance = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(
        context,
        details.primaryVelocity ?? 0.0,
      ),
      child: Consumer<MinorHqState>(
        builder: (context, state, child) {
          final pages = state.pages;

          final safeIndex = pages.isEmpty ? 0 : state.selectedIndex.clamp(0, pages.length - 1);

          final children = pages.isEmpty ? const <Widget>[SizedBox.shrink()] : pages.map((p) => p.page).toList();

          return Stack(
            children: [
              IndexedStack(
                index: safeIndex,
                children: children,
              ),
              if (state.isLoading)
                Container(
                  color: cs.surface.withOpacity(.35),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
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
    final cs = Theme.of(context).colorScheme;

    return Consumer<MinorHqState>(
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
          selectedItemColor: cs.primary,
          unselectedItemColor: cs.onSurfaceVariant.withOpacity(.75),
          backgroundColor: cs.surface,
          elevation: 0,
          showUnselectedLabels: true,
        );
      },
    );
  }
}
