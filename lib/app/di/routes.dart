import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../features/community/page/community_stub_page.dart';
import '../../features/community/page/faq_page.dart';
import '../../features/commute/page/double/double_commute_in_screen.dart';
import '../../features/commute/page/headquarter/headquarter_commute_in_screen.dart';
import '../../features/commute/page/minor/minor_commute_in_screen.dart';
import '../../features/commute/page/single/single_commute_in_screen.dart';
import '../../features/commute/page/triple/triple_commute_in_screen.dart';
import '../../features/commute/widgets/commute_destination_cinematic_entry.dart';
import '../../features/dashboard/pages/common/headquarter_page.dart';
import '../../features/description/pages/description_page.dart';
import '../../features/dev/page/dev_stub_page.dart';
import '../../features/headquarter/page/head_stub_page.dart';
import '../../features/login/pages/common/login_screen.dart';
import '../../features/mode_single/page/single_inside_screen.dart';
import '../../features/novel/presentation/novel_mobile_writing_page.dart';
import '../../features/sprint/pages/sprint_mode_loading_page.dart';
import '../../features/personal/pages/personal_page.dart';
import '../terminal/presentation/parkinworkin_terminal_screen.dart';
import '../utils/status_dialog.dart';
import '../../features/selector/application/dev_auth.dart';
import '../../features/launcher/page/power_boot_screen.dart';
import '../../features/tablet/pages/tablet_page.dart';
import '../../shared/page/pages/double/double_type_page.dart';
import '../../shared/page/pages/minor/minor_type_page.dart';
import '../../shared/page/pages/triple/triple_type_page.dart';
import '../space/practice_space_lab_screen.dart';
import '../tutorial/tutorial/start_gate_screen.dart';
import '../init/startup_tasks.dart';

class AppRoutes {
  static const startGate = '/';
  static const appStartTutorial = '/app_start_tutorial';
  static const appStartSetupWorkflow = '/app_start_setup_workflow';
  static const appStartUserPurpose = '/app_start_user_purpose';
  static const appStartPermissionNotice = '/app_start_permission_notice';
  static const appStartPermissionSetup = '/app_start_permission_setup';
  static const appStartNextTutorialFull = '/app_start_next_tutorial_full';
  static const appStartNextTutorialQuick = '/app_start_next_tutorial_quick';
  static const appStartFinish = '/app_start_finish';
  static const termsConsent = '/app_start_terms_consent';
  static const privacyPolicyConsent = '/app_start_privacy_policy_consent';
  static const accountDeletionPolicyConsent =
      '/app_start_account_deletion_policy_consent';
  static const appStartGoogleServicesSetup =
      '/app_start_google_services_setup';
  static const powerBoot = '/power_boot';
  static const modeLauncher = '/mode_launcher';
  static const descriptionIntro = '/description_intro';

  static const serviceLogin = '/service_login';
  static const personalLogin = '/personal_login';
  static const tabletLogin = '/tablet_login';
  static const doubleLogin = '/double_login';
  static const singleLogin = '/single_login';
  static const tripleLogin = '/triple_login';
  static const minorLogin = '/minor_login';
  static const practiceSpaceLab = '/practiceSpaceLab';

  static const commute = '/commute';
  static const singleCommute = '/single_commute';
  static const singleInside = '/single_inside';
  static const doubleCommute = '/double_commute';
  static const tripleCommute = '/triple_commute';
  static const minorCommute = '/minor_commute';

  static const headquarterCommute = '/headquarter_commute';
  static const headquarterPage = '/headquarter_page';
  static const singleHeadquarterPage = '/single_headquarter_page';
  static const doubleHeadquarterPage = '/double_headquarter_page';
  static const tripleHeadquarterPage = '/triple_headquarter_page';
  static const minorHeadquarterPage = '/minor_headquarter_page';

  static const typePage = '/type_page';
  static const doubleTypePage = '/double_type_page';
  static const tripleTypePage = '/triple_type_page';
  static const minorTypePage = '/minor_type_page';

  static const tablet = '/tablet_page';
  static const personal = '/personal_page';
  static const sprintModeLoading = '/sprint_mode_loading';
  static const sprintModeHome = '/sprint_mode_home';
  static const faq = '/faq';

  static const communityStub = '/community_stub';
  static const headStub = '/head_stub';
  static const devStub = '/dev_stub';

  static const laborGuide = '/labor_guide';

  static const noteSystem = '/notensystem';
}

Widget _buildPowerBootPage(BuildContext context) {
  final arguments = ModalRoute.of(context)?.settings.arguments;
  final report = arguments is StartupReport ? arguments : StartupTasks.lastReport;
  return PowerBootScreen(startupReport: report);
}

Widget _buildModeLauncherPage(BuildContext context) {
  final arguments = ModalRoute.of(context)?.settings.arguments;
  final report = arguments is StartupReport ? arguments : StartupTasks.lastReport;
  return ParkinWorkinTerminalScreen.launcher(startupReport: report);
}

Widget _buildSprintModeLoadingPage(BuildContext context) {
  final arguments = ModalRoute.of(context)?.settings.arguments;
  String? returnRouteName;
  if (arguments is Map) {
    final value = arguments['returnRouteName'];
    if (value is String && value.trim().isNotEmpty) {
      returnRouteName = value.trim();
    }
  }
  return SprintModeLoadingPage(returnRouteName: returnRouteName);
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.startGate: (context) => const StartGateScreen(),
  AppRoutes.appStartTutorial: (context) => const StartGateScreen(),
  AppRoutes.appStartSetupWorkflow: (context) => const StartGateScreen(),
  AppRoutes.appStartUserPurpose: (context) => const StartGateScreen(),
  AppRoutes.appStartPermissionNotice: (context) => const StartGateScreen(),
  AppRoutes.appStartPermissionSetup: (context) => const StartGateScreen(),
  AppRoutes.appStartNextTutorialFull: (context) => const StartGateScreen(),
  AppRoutes.appStartNextTutorialQuick: (context) => const StartGateScreen(),
  AppRoutes.appStartFinish: (context) => const StartGateScreen(),
  AppRoutes.termsConsent: (context) => const StartGateScreen(),
  AppRoutes.privacyPolicyConsent: (context) => const StartGateScreen(),
  AppRoutes.accountDeletionPolicyConsent: (context) => const StartGateScreen(),
  AppRoutes.appStartGoogleServicesSetup: (context) => const StartGateScreen(),
  AppRoutes.powerBoot: _buildPowerBootPage,
  AppRoutes.modeLauncher: _buildModeLauncherPage,
  AppRoutes.descriptionIntro: (context) => const DescriptionPage(),
  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.personalLogin: _buildModeLauncherPage,
  AppRoutes.tabletLogin: _buildModeLauncherPage,
  AppRoutes.singleLogin: _buildModeLauncherPage,
  AppRoutes.doubleLogin: _buildModeLauncherPage,
  AppRoutes.tripleLogin: _buildModeLauncherPage,
  AppRoutes.minorLogin: _buildModeLauncherPage,
  AppRoutes.practiceSpaceLab: (context) => const PracticeSpaceLabScreen(),
  AppRoutes.singleInside: (context) => const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.singleInside,
        child: SingleInsideScreen(),
      ),
  AppRoutes.headquarterPage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.headquarterPage,
        child: HeadquarterPage(),
      ),
  AppRoutes.singleHeadquarterPage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.singleHeadquarterPage,
        child: HeadquarterPage(),
      ),
  AppRoutes.doubleHeadquarterPage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.doubleHeadquarterPage,
        child: HeadquarterPage(),
      ),
  AppRoutes.tripleHeadquarterPage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.tripleHeadquarterPage,
        child: HeadquarterPage(),
      ),
  AppRoutes.minorHeadquarterPage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.minorHeadquarterPage,
        child: HeadquarterPage(),
      ),
  AppRoutes.doubleTypePage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.doubleTypePage,
        child: DoubleTypePage(),
      ),
  AppRoutes.tripleTypePage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.tripleTypePage,
        child: TripleTypePage(),
      ),
  AppRoutes.minorTypePage: (context) =>
      const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.minorTypePage,
        child: MinorTypePage(),
      ),
  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.personal: (context) => const PersonalPage(),
  AppRoutes.sprintModeLoading: _buildSprintModeLoadingPage,
  AppRoutes.sprintModeHome: _buildSprintModeLoadingPage,
  AppRoutes.faq: (context) => const FaqPage(),
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),
  AppRoutes.noteSystem: (context) => const NovelMobileWritingPage(),
};

WidgetBuilder? resolveCommuteRouteBuilder(String routeName) {
  switch (routeName) {
    case AppRoutes.headquarterCommute:
      return (context) => const HeadquarterCommuteInScreen();
    case AppRoutes.singleCommute:
      return (context) => const SingleCommuteInScreen();
    case AppRoutes.doubleCommute:
      return (context) => const DoubleCommuteInScreen();
    case AppRoutes.tripleCommute:
      return (context) => const TripleCommuteInScreen();
    case AppRoutes.minorCommute:
      return (context) => const MinorCommuteInScreen();
    default:
      return null;
  }
}

WidgetBuilder? resolveAppRouteBuilder(String routeName) {
  return appRoutes[routeName] ?? resolveCommuteRouteBuilder(routeName);
}

String appRouteResolverSource(String routeName) {
  if (appRoutes.containsKey(routeName)) {
    return 'app_routes';
  }
  if (resolveCommuteRouteBuilder(routeName) != null) {
    return 'commute_resolver';
  }
  return 'none';
}

Route<dynamic>? onGenerateAppRoute(RouteSettings settings) {
  final routeName = settings.name?.trim() ?? '';
  if (routeName.isEmpty) return null;

  final builder = resolveCommuteRouteBuilder(routeName);
  if (builder == null) return null;

  final reduceMotion = WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  final transitionDuration =
      reduceMotion ? Duration.zero : const Duration(milliseconds: 620);
  final reverseTransitionDuration =
      reduceMotion ? Duration.zero : const Duration(milliseconds: 320);

  debugPrint(
    '[COMMUTE-MONITOR][${DateTime.now().toIso8601String()}] route create route=$routeName reduceMotion=$reduceMotion transitionMs=${transitionDuration.inMilliseconds}',
  );

  return PageRouteBuilder<dynamic>(
    settings: settings,
    opaque: true,
    barrierDismissible: false,
    transitionDuration: transitionDuration,
    reverseTransitionDuration: reverseTransitionDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return _CommuteMonitorPowerOnTransition(
        animation: animation,
        routeName: routeName,
        reduceMotion: reduceMotion,
        transitionDuration: transitionDuration,
        child: child,
      );
    },
  );
}

class _CommuteMonitorPowerOnTransition extends StatefulWidget {
  const _CommuteMonitorPowerOnTransition({
    required this.animation,
    required this.routeName,
    required this.reduceMotion,
    required this.transitionDuration,
    required this.child,
  });

  final Animation<double> animation;
  final String routeName;
  final bool reduceMotion;
  final Duration transitionDuration;
  final Widget child;

  @override
  State<_CommuteMonitorPowerOnTransition> createState() =>
      _CommuteMonitorPowerOnTransitionState();
}

class _CommuteMonitorPowerOnTransitionState
    extends State<_CommuteMonitorPowerOnTransition> {
  static const Color _beamColor = Color(0xFF8AE234);
  final List<String> _debugLines = <String>[];
  bool _completionHandled = false;
  bool _statusDialogRequested = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleAnimationStatus);
    _log(
      'start route=${widget.routeName} reduceMotion=${widget.reduceMotion} transitionMs=${widget.transitionDuration.inMilliseconds}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.reduceMotion || widget.animation.isCompleted) {
        _handleCompleted();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CommuteMonitorPowerOnTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_handleAnimationStatus);
      widget.animation.addStatusListener(_handleAnimationStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleAnimationStatus);
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _handleCompleted();
    }
  }

  void _handleCompleted() {
    if (_completionHandled) return;
    _completionHandled = true;
    _log(
      'complete route=${widget.routeName} reduceMotion=${widget.reduceMotion} horizontalSlide=false monitorPowerOn=true',
    );
    unawaited(_showDeveloperStatusDialog());
  }

  void _log(String message) {
    final line =
        '[COMMUTE-MONITOR][${DateTime.now().toIso8601String()}] $message';
    _debugLines.add(line);
    debugPrint(line);
  }

  Future<void> _showDeveloperStatusDialog() async {
    if (_statusDialogRequested) return;
    _statusDialogRequested = true;

    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !mounted) return;

    final lines = List<String>.from(_debugLines);
    final description = lines.join('\n');
    final copyText = lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');

    await StatusDialog.showSuccess(
      context,
      title: '출근 화면 전환 디버그',
      description: description,
      copyText: copyText,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      awaitManualClose: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final value = widget.animation.value.clamp(0.0, 1.0).toDouble();
        final horizontal = Curves.easeOutCubic.transform(
          (value / 0.38).clamp(0.0, 1.0).toDouble(),
        );
        final vertical = Curves.easeOutCubic.transform(
          ((value - 0.18) / 0.50).clamp(0.0, 1.0).toDouble(),
        );
        final contentOpacity = Curves.easeOutCubic.transform(
          ((value - 0.48) / 0.52).clamp(0.0, 1.0).toDouble(),
        );
        final beamOpacity = value < 0.58
            ? (1 - ((value - 0.24) / 0.34).clamp(0.0, 1.0)).toDouble()
            : 0.0;
        final glowOpacity = value < 0.68
            ? (1 - ((value - 0.20) / 0.48).clamp(0.0, 1.0)).toDouble()
            : 0.0;
        final settleScale = 0.992 + (0.008 * contentOpacity);

        return ColoredBox(
          color: Colors.black,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IgnorePointer(
                    ignoring: widget.animation.status != AnimationStatus.completed,
                    child: Transform.scale(
                      scaleX: horizontal < 0.012 ? 0.012 : horizontal,
                      scaleY: vertical < 0.004 ? 0.004 : vertical,
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: contentOpacity,
                        child: Transform.scale(
                          scale: settleScale,
                          alignment: Alignment.center,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Opacity(
                      opacity: glowOpacity * 0.72,
                      child: Container(
                        width: width * horizontal,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _beamColor.withOpacity(0.14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x998AE234),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Opacity(
                      opacity: beamOpacity,
                      child: Container(
                        width: width * horizontal,
                        height: 2,
                        color: _beamColor,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

