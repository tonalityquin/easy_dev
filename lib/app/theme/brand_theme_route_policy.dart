import '../di/routes.dart';

enum BrandThemeRoutePhase {
  preWork,
  workspace,
  unchanged,
}

class BrandThemeRoutePolicy {
  BrandThemeRoutePolicy._();

  static const Set<String> _preWorkRoutes = <String>{
    AppRoutes.startGate,
    AppRoutes.appStartTutorial,
    AppRoutes.appStartSetupWorkflow,
    AppRoutes.appStartUserPurpose,
    AppRoutes.appStartPermissionNotice,
    AppRoutes.appStartPermissionSetup,
    AppRoutes.appStartNextTutorialFull,
    AppRoutes.appStartNextTutorialQuick,
    AppRoutes.appStartFinish,
    AppRoutes.termsConsent,
    AppRoutes.privacyPolicyConsent,
    AppRoutes.accountDeletionPolicyConsent,
    AppRoutes.appStartGoogleServicesSetup,
    AppRoutes.powerBoot,
    AppRoutes.modeLauncher,
    AppRoutes.descriptionIntro,
    AppRoutes.serviceLogin,
    AppRoutes.personalLogin,
    AppRoutes.tabletLogin,
    AppRoutes.singleLogin,
    AppRoutes.doubleLogin,
    AppRoutes.tripleLogin,
    AppRoutes.minorLogin,
    AppRoutes.commute,
    AppRoutes.headquarterCommute,
    AppRoutes.singleCommute,
    AppRoutes.doubleCommute,
    AppRoutes.tripleCommute,
    AppRoutes.minorCommute,
    AppRoutes.devStub,
  };

  static const Set<String> _workspaceRoutes = <String>{
    AppRoutes.singleInside,
    AppRoutes.headquarterPage,
    AppRoutes.singleHeadquarterPage,
    AppRoutes.doubleHeadquarterPage,
    AppRoutes.tripleHeadquarterPage,
    AppRoutes.minorHeadquarterPage,
    AppRoutes.typePage,
    AppRoutes.doubleTypePage,
    AppRoutes.tripleTypePage,
    AppRoutes.minorTypePage,
    AppRoutes.tablet,
    AppRoutes.personal,
  };

  static BrandThemeRoutePhase resolve(String? routeName) {
    final normalized = routeName?.trim() ?? '';
    if (normalized.isEmpty) return BrandThemeRoutePhase.unchanged;
    if (_preWorkRoutes.contains(normalized)) {
      return BrandThemeRoutePhase.preWork;
    }
    if (_workspaceRoutes.contains(normalized)) {
      return BrandThemeRoutePhase.workspace;
    }
    return BrandThemeRoutePhase.unchanged;
  }
}
