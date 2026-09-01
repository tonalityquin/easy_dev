import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/command/presentation/terminal_launcher_button.dart';
import '../../../../app/init/db_connection_status_section.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../headquarter/application/headquarter_dashboard_context.dart';
import 'common_hq_dash_board_page.dart';

class HeadquarterPage extends StatelessWidget {
  const HeadquarterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonUiScope(
      child: _HeadquarterDashboardShell(),
    );
  }
}

class _HeadquarterDashboardShell extends StatefulWidget {
  const _HeadquarterDashboardShell();

  @override
  State<_HeadquarterDashboardShell> createState() =>
      _HeadquarterDashboardShellState();
}

class _HeadquarterDashboardShellState extends State<_HeadquarterDashboardShell> {
  static const String _screenTagAsset = 'assets/images/pelican_text.png';
  static const Size _screenTagSize = Size(104, 38);
  static const double _hDistanceThreshold = 80;
  static const double _hVelocityThreshold = 1000;

  double _dragDistance = 0;
  bool _openingSecondary = false;

  @override
  void initState() {
    super.initState();
    HeadquarterDashboardContext.clearMode(
      source: 'headquarter_page_init',
    );
    debugPrint(
      '[HQ-PAGE][${DateTime.now().toIso8601String()}] context=headquarter mode=none modeIndependent=true prefsModeRead=false prefsModeWrite=false additionalFirebaseRead=0 additionalFirebaseWrite=0',
    );
  }

  Future<void> _openSecondaryIfAuthorized() async {
    if (_openingSecondary) return;
    _openingSecondary = true;
    try {
      final restored = await DevAuth.restorePrefs();
      if (!mounted || !restored.devAuthorized) return;
      debugPrint(
        '[HQ-PAGE][${DateTime.now().toIso8601String()}] secondary_open source=headquarter_page additionalFirebaseRead=0 additionalFirebaseWrite=0',
      );
      await showSecondarySideDock<void>(
        context: context,
        barrierLabel: '운영 관리',
      );
      debugPrint(
        '[HQ-PAGE][${DateTime.now().toIso8601String()}] secondary_close source=headquarter_page additionalFirebaseRead=0 additionalFirebaseWrite=0',
      );
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
    final tokens = CommonUiTheme.of(context);
    final overlayStyle =
        tokens.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: tokens.surface,
        systemNavigationBarColor: tokens.canvas,
        systemNavigationBarDividerColor: tokens.borderSubtle,
      ),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: tokens.canvas,
          appBar: AppBar(
            title: const TerminalLauncherButton(source: 'headquarter'),
            centerTitle: true,
            backgroundColor: tokens.surface,
            foregroundColor: tokens.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: tokens.transparent,
            shape: Border(
              bottom: BorderSide(color: tokens.borderSubtle),
            ),
            flexibleSpace: SafeArea(
              child: Stack(
                children: [
                  IgnorePointer(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, top: 5),
                        child: CommonAnimatedReveal(
                          offset: const Offset(-0.04, 0),
                          child: SizedBox(
                            width: _screenTagSize.width,
                            height: _screenTagSize.height,
                            child: Image.asset(
                              _screenTagAsset,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              color: tokens.textSecondary,
                              colorBlendMode: BlendMode.srcIn,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: 12,
                          top: 8,
                          bottom: 8,
                        ),
                        child: SizedBox(
                          height: kToolbarHeight - 8,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: DbConnectionStatusAppBarSection(
                                liveLabel: 'live DB',
                                storageLabel: '스토리지 DB',
                                spacing: 4,
                                useCommonUi: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragUpdate: (details) {
              _dragDistance += details.delta.dx;
            },
            onHorizontalDragEnd: (details) {
              _handleHorizontalDragEnd(details.primaryVelocity ?? 0);
            },
            child: const CommonHqDashBoardPage(
              screenName: 'headquarter_dashboard',
              modeKey: '',
            ),
          ),
        ),
      ),
    );
  }
}
