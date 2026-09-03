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
import '../../features/launcher/page/power_boot_screen.dart';
import '../../features/tablet/pages/tablet_page.dart';
import '../../shared/page/pages/double/double_type_page.dart';
import '../../shared/page/pages/minor/minor_type_page.dart';
import '../../shared/page/pages/triple/triple_type_page.dart';
import '../space/practice_space_lab_screen.dart';
import '../tutorial/policy/app_start_google_services_setup_screen.dart';
import '../tutorial/policy/policy_consent_screen.dart';
import '../tutorial/tutorial/app_start_permission_notice_screen.dart';
import '../tutorial/tutorial/app_start_permission_setup_screen.dart';
import '../tutorial/tutorial/app_start_user_purpose_screen.dart';
import '../tutorial/tutorial/start_gate_screen.dart';
import '../init/startup_tasks.dart';

class AppRoutes {
  static const startGate = '/';
  static const appStartTutorial = '/app_start_tutorial';
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
  AppRoutes.appStartTutorial: (context) => const AppStartUserPurposeScreen(),
  AppRoutes.appStartUserPurpose: (context) =>
      const AppStartUserPurposeScreen(),
  AppRoutes.appStartPermissionNotice: (context) =>
      const AppStartPermissionNoticeScreen(),
  AppRoutes.appStartPermissionSetup: (context) =>
      const AppStartPermissionSetupScreen(),
  AppRoutes.appStartNextTutorialFull: (context) => const StartGateScreen(),
  AppRoutes.appStartNextTutorialQuick: (context) => const StartGateScreen(),
  AppRoutes.appStartFinish: (context) => const StartGateScreen(),
  AppRoutes.termsConsent: (context) => const PolicyConsentScreen(
        kind: PolicyConsentKind.termsOfService,
      ),
  AppRoutes.privacyPolicyConsent: (context) => const PolicyConsentScreen(
        kind: PolicyConsentKind.privacyPolicy,
      ),
  AppRoutes.accountDeletionPolicyConsent: (context) => const PolicyConsentScreen(
        kind: PolicyConsentKind.accountDeletion,
      ),
  AppRoutes.appStartGoogleServicesSetup: (context) =>
      const AppStartGoogleServicesSetupScreen(),
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
  AppRoutes.headquarterCommute: (context) => const HeadquarterCommuteInScreen(),
  AppRoutes.doubleCommute: (context) => const DoubleCommuteInScreen(),
  AppRoutes.singleCommute: (context) => const SingleCommuteInScreen(),
  AppRoutes.singleInside: (context) => const CommuteDestinationCinematicEntry(
        routeName: AppRoutes.singleInside,
        child: SingleInsideScreen(),
      ),
  AppRoutes.tripleCommute: (context) => const TripleCommuteInScreen(),
  AppRoutes.minorCommute: (context) => const MinorCommuteInScreen(),
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
