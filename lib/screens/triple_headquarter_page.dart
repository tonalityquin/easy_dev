import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../selector_hubs_package/dev_auth.dart';
import '../states/page/triple_hq_state.dart';
import '../states/page/triple_page_info.dart';
import '../states/plate/plate_state.dart';
import '../states/plate/triple_plate_state.dart';
import '../theme.dart';
import 'hubs_mode/dev_package/debug_package/debug_action_recorder.dart';
import 'secondary_page.dart';

class TripleHeadquarterPage extends StatelessWidget {
  const TripleHeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TripleHqState(pages: tripleHqPage)),
      ],
      child: Builder(
        builder: (context) {
          return PopScope(
            canPop: false,
            child: Scaffold(
              body: const _RefreshableBody(),
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
    final state = context.watch<TripleHqState>();
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
        _PageBottomNavigation(),
        _BrandFooter(),
      ],
    );
  }
}

@immutable
class _ModeTarget {
  const _ModeTarget({
    required this.title,
    required this.routeName,
    required this.icon,
    required this.modeKey,
  });

  final String title;
  final String routeName;
  final IconData icon;
  final String modeKey;
}

class _HqModeSwitchButton extends StatelessWidget {
  const _HqModeSwitchButton();

  static const List<_ModeTarget> _targets = <_ModeTarget>[
    _ModeTarget(
      title: '마이너 헤드쿼터로 이동',
      routeName: AppRoutes.minorHeadquarterPage,
      icon: Icons.tune,
      modeKey: 'minor',
    ),
    _ModeTarget(
      title: '더블 헤드쿼터로 이동',
      routeName: AppRoutes.doubleHeadquarterPage,
      icon: Icons.view_week,
      modeKey: 'double',
    ),
  ];

  void _trace(BuildContext context, String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<_ModeTarget?> _pickTarget(BuildContext context, AppCardPalette palette) {
    final accent = palette.tripleBase;
    final border = palette.tripleLight.withOpacity(.65);
    final textColor = palette.tripleDark;

    return showDialog<_ModeTarget>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '헤드쿼터 모드 전환',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(Icons.close, color: textColor.withOpacity(.75)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._targets.map(
                      (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ModeSwitchDialogOption(
                      title: t.title,
                      icon: t.icon,
                      accentColor: accent,
                      borderColor: border,
                      textColor: textColor,
                      onTap: () => Navigator.of(dialogContext).pop(t),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('헤드쿼터 모드 전환'),
          style: _switchBtnStyle(context),
          onPressed: () async {
            final target = await _pickTarget(context, palette);
            if (target == null) return;

            _trace(
              context,
              '헤드쿼터 모드 전환',
              meta: <String, dynamic>{
                'screen': 'triple_headquarter_page',
                'action': 'switch_headquarter_mode',
                'from': 'triple',
                'to': target.modeKey,
                'toRoute': target.routeName,
              },
            );

            context.read<TriplePlateState>().tripleDisableAll();
            context.read<PlateState>().disableAll();

            _replaceWithAnimatedRoute(
              context,
              target.routeName,
              beginOffset: const Offset(-1.0, 0.0),
            );
          },
        ),
      ),
    );
  }
}

class _ModeSwitchDialogOption extends StatelessWidget {
  const _ModeSwitchDialogOption({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: textColor.withOpacity(.6)),
            ],
          ),
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

class _RefreshableBody extends StatefulWidget {
  const _RefreshableBody();

  @override
  State<_RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<_RefreshableBody> {
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
      child: Consumer<TripleHqState>(
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
                          palette.tripleBase,
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

class _PageBottomNavigation extends StatelessWidget {
  const _PageBottomNavigation();

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);

    return Consumer<TripleHqState>(
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
          selectedItemColor: palette.tripleBase,
          unselectedItemColor: palette.tripleDark.withOpacity(.55),
          backgroundColor: Colors.white,
          elevation: 0,
          showUnselectedLabels: true,
        );
      },
    );
  }
}

ButtonStyle _switchBtnStyle(BuildContext context) {
  final palette = AppCardPalette.of(context);

  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: palette.tripleDark,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: BorderSide(
      color: palette.tripleLight.withOpacity(.8),
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
