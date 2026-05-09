import 'package:flutter/material.dart';
import '../../features/community/page/community_stub_page.dart';
import '../../features/community/page/faq_page.dart';
import '../../features/commute/page/double/double_commute_in_screen.dart';
import '../../features/commute/page/minor/minor_commute_in_screen.dart';
import '../../features/commute/page/triple/triple_commute_in_screen.dart';
import '../../features/dashboard/pages/double/double_headquarter_page.dart';
import '../../features/dashboard/pages/minor/minor_headquarter_page.dart';
import '../../features/dashboard/pages/triple/triple_headquarter_page.dart';
import '../../features/description/pages/description_page.dart';
import '../../features/dev/page/dev_stub_page.dart';
import '../../features/dev/page/sheets/dev_calendar_page.dart';
import '../../features/headquarter/page/head_stub_page.dart';
import '../../features/headquarter/page/sheets/company_calendar_page.dart';
import '../../features/headquarter/page/sheets/timesheet_page.dart';
import '../../features/login/pages/common/login_screen.dart';
import '../../features/mode_single/page/single_inside_screen.dart';
import '../../features/selector/page/selector_hubs_page.dart';
import '../../features/tablet/pages/tablet_page.dart';
import '../../features/voice/page/voice/voice_page.dart';
import '../../shared/page/pages/double/double_type_page.dart';
import '../../shared/page/pages/minor/minor_type_page.dart';
import '../../shared/page/pages/triple/triple_type_page.dart';
import '../space/practice_space_lab_screen.dart';
import '../tutorial/tutorial/app_start_finish_screen.dart';
import '../tutorial/tutorial/app_start_next_tutorial_full_screen.dart';
import '../tutorial/tutorial/app_start_next_tutorial_quick_screen.dart';
import '../tutorial/tutorial/app_start_tutorial_lab_screen.dart';
import '../tutorial/tutorial/start_gate_screen.dart';

class AppRoutes {
  static const startGate = '/';
  static const appStartTutorial = '/app_start_tutorial';
  static const appStartNextTutorialFull = '/app_start_next_tutorial_full';
  static const appStartNextTutorialQuick = '/app_start_next_tutorial_quick';
  static const appStartFinish = '/app_start_finish';
  static const selector = '/selector';
  static const descriptionIntro = '/description_intro';

  static const serviceLogin = '/service_login';
  static const tabletLogin = '/tablet_login';
  static const doubleLogin = '/double_login';
  static const singleLogin = '/single_login';
  static const tripleLogin = '/triple_login';
  static const minorLogin = '/minor_login';
  static const practiceSpaceLab = '/practiceSpaceLab';

  static const commute = '/commute';
  static const singleCommute = '/single_commute';
  static const doubleCommute = '/double_commute';
  static const tripleCommute = '/triple_commute';
  static const minorCommute = '/minor_commute';

  static const headquarterPage = '/headquarter_page';
  static const doubleHeadquarterPage = '/double_headquarter_page';
  static const tripleHeadquarterPage = '/triple_headquarter_page';
  static const minorHeadquarterPage = '/minor_headquarter_page';

  static const typePage = '/type_page';
  static const doubleTypePage = '/double_type_page';
  static const tripleTypePage = '/triple_type_page';
  static const minorTypePage = '/minor_type_page';

  static const tablet = '/tablet_page';
  static const faq = '/faq';

  static const communityStub = '/community_stub';
  static const communityWorkintalkin = '/community_workintalkin';
  static const headStub = '/head_stub';
  static const devStub = '/dev_stub';

  static const companyCalendar = '/company_calendar';
  static const devCalendar = '/dev_calendar';
  static const laborGuide = '/labor_guide';

  static const attendanceSheet = '/attendance_sheet';
  static const breakSheet = '/break_sheet';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.startGate: (context) => const StartGateScreen(),
  AppRoutes.appStartTutorial: (context) => const AppStartTutorialLabScreen(),
  AppRoutes.appStartNextTutorialFull: (context) => const AppStartNextTutorialFullScreen(),
  AppRoutes.appStartNextTutorialQuick: (context) => const AppStartNextTutorialQuickScreen(),
  AppRoutes.appStartFinish: (context) => const AppStartFinishScreen(),
  AppRoutes.selector: (context) => const SelectorHubsPage(),
  AppRoutes.descriptionIntro: (context) => const DescriptionPage(),

  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),
  AppRoutes.singleLogin: (context) => const LoginScreen(mode: 'single'),
  AppRoutes.doubleLogin: (context) => const LoginScreen(mode: 'double'),
  AppRoutes.tripleLogin: (context) => const LoginScreen(mode: 'triple'),
  AppRoutes.minorLogin: (context) => const LoginScreen(mode: 'minor'),
  AppRoutes.practiceSpaceLab: (context) => const PracticeSpaceLabScreen(),

  AppRoutes.doubleCommute: (context) => const DoubleCommuteInScreen(),
  AppRoutes.singleCommute: (context) => const SingleInsideScreen(),
  AppRoutes.tripleCommute: (context) => const TripleCommuteInScreen(),
  AppRoutes.minorCommute: (context) => const MinorCommuteInScreen(),

  AppRoutes.doubleHeadquarterPage: (context) => const DoubleHeadquarterPage(),
  AppRoutes.tripleHeadquarterPage: (context) => const TripleHeadquarterPage(),
  AppRoutes.minorHeadquarterPage: (context) => const MinorHeadquarterPage(),

  AppRoutes.doubleTypePage: (context) => const DoubleTypePage(),
  AppRoutes.tripleTypePage: (context) => const TripleTypePage(),
  AppRoutes.minorTypePage: (context) => const MinorTypePage(),

  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.faq: (context) => const FaqPage(),

  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.communityWorkintalkin: (context) => const VoicePage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),

  AppRoutes.companyCalendar: (context) => const CompanyCalendarPage(),
  AppRoutes.devCalendar: (context) => const DevCalendarPage(),

  AppRoutes.attendanceSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.attendance),
  AppRoutes.breakSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.breakTime),
};
