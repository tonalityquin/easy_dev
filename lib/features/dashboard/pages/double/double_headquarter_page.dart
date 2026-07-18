import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../shared/page/application/double/double_page_info.dart';
import '../../../../shared/plate/application/double/double_plate_state.dart';
import '../../../../shared/secondary/pages/secondary_page.dart';
import '../../../selector/application/dev_auth.dart';
import '../../applications/double/double_hq_state.dart';
import '../../widgets/headquarter_mode_switch_button.dart';

class DoubleHeadquarterPage extends StatelessWidget {
  const DoubleHeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DoubleHqState(pages: doubleHqPage)),
      ],
      child: const PromptUiScope(
        child: _DoubleHeadquarterShell(),
      ),
    );
  }
}

class _DoubleHeadquarterShell extends StatelessWidget {
  const _DoubleHeadquarterShell();

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: tokens.canvas,
        body: const RefreshableBody(),
        bottomNavigationBar: const SafeArea(
          top: false,
          child: _BottomArea(),
        ),
      ),
    );
  }
}

class _BottomArea extends StatelessWidget {
  const _BottomArea();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DoubleHqState>();
    final pages = state.pages;
    final switchButton = HeadquarterModeSwitchButton(
      currentModeKey: 'double',
      currentScreen: 'double_headquarter_page',
      onBeforeSwitch: () => context.read<DoublePlateState>().doubleDisableAll(),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: PromptUiTheme.of(context).surface,
        border: Border(
          top: BorderSide(color: PromptUiTheme.of(context).borderSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pages.length >= 2) const PageBottomNavigation(),
          switchButton,
        ],
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
  double _dragDistance = 0;
  bool _openingSecondary = false;

  static const double _hDistanceThreshold = 80;
  static const double _hVelocityThreshold = 1000;

  Future<bool> _isDevAuthorized() async {
    final restored = await DevAuth.restorePrefs();
    return restored.devAuthorized;
  }

  PageRouteBuilder<void> _slidePage(Widget page) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : PromptUiMotion.overlay;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: PromptUiMotion.enter,
          reverseCurve: PromptUiMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openSecondaryIfAuthorized() async {
    if (_openingSecondary) return;
    _openingSecondary = true;
    try {
      final ok = await _isDevAuthorized();
      if (!mounted || !ok) return;
      Navigator.of(context).push(_slidePage(const SecondaryPage()));
    } finally {
      _openingSecondary = false;
    }
  }

  void _handleHorizontalDragEnd(double velocity) {
    final fired = _dragDistance < -_hDistanceThreshold &&
        velocity < -_hVelocityThreshold;
    if (fired) _openSecondaryIfAuthorized();
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) =>
          _handleHorizontalDragEnd(details.primaryVelocity ?? 0),
      child: Consumer<DoubleHqState>(
        builder: (context, state, child) {
          final pages = state.pages;
          final safeIndex = pages.isEmpty
              ? 0
              : state.selectedIndex.clamp(0, pages.length - 1);
          final children = pages.isEmpty
              ? const <Widget>[SizedBox.shrink()]
              : pages.map((page) => page.page).toList(growable: false);
          return Stack(
            children: [
              IndexedStack(index: safeIndex, children: children),
              IgnorePointer(
                ignoring: !state.isLoading,
                child: AnimatedOpacity(
                  opacity: state.isLoading ? 1 : 0,
                  duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                      ? Duration.zero
                      : PromptUiMotion.component,
                  child: ColoredBox(
                    color: tokens.scrim.withOpacity(tokens.isDark ? 0.30 : 0.14),
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          borderRadius: BorderRadius.circular(PromptUiShapes.card),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: tokens.accent,
                          ),
                        ),
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
    final tokens = PromptUiTheme.of(context);
    return Consumer<DoubleHqState>(
      builder: (context, state, child) {
        final pages = state.pages;
        if (pages.length < 2) return const SizedBox.shrink();
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
              .toList(growable: false),
          selectedItemColor: tokens.accent,
          unselectedItemColor: tokens.textSecondary,
          backgroundColor: tokens.surface,
          elevation: 0,
          showUnselectedLabels: true,
        );
      },
    );
  }
}
