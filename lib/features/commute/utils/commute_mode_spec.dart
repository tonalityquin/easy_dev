import '../../../app/di/routes.dart';

class CommuteModeSpec {
  final String contextKey;
  final String modeKey;
  final String screenTagLabel;
  final String headquarterRoute;
  final String typeRoute;
  final bool isHeadquarterContext;
  final bool enableDebugTrace;
  final String? traceScreenId;
  final String? saveLogPrefix;

  const CommuteModeSpec({
    required this.contextKey,
    required this.modeKey,
    required this.screenTagLabel,
    required this.headquarterRoute,
    required this.typeRoute,
    required this.isHeadquarterContext,
    required this.enableDebugTrace,
    this.traceScreenId,
    this.saveLogPrefix,
  });

  String get diagnosticKey => contextKey.trim().isEmpty ? modeKey : contextKey;

  static const CommuteModeSpec headquarter = CommuteModeSpec(
    contextKey: 'headquarter',
    modeKey: '',
    screenTagLabel: 'screen_tag: headquarter commute screen',
    headquarterRoute: AppRoutes.headquarterPage,
    typeRoute: AppRoutes.headquarterPage,
    isHeadquarterContext: true,
    enableDebugTrace: true,
    traceScreenId: 'headquarter_commute_inside',
    saveLogPrefix: 'Headquarter',
  );

  static const CommuteModeSpec singleMode = CommuteModeSpec(
    contextKey: 'single',
    modeKey: 'single',
    screenTagLabel: 'screen_tag: single commute screen',
    headquarterRoute: AppRoutes.headquarterPage,
    typeRoute: AppRoutes.singleInside,
    isHeadquarterContext: false,
    enableDebugTrace: true,
    traceScreenId: 'single_commute_inside',
    saveLogPrefix: 'Single',
  );

  static const CommuteModeSpec doubleMode = CommuteModeSpec(
    contextKey: 'double',
    modeKey: 'double',
    screenTagLabel: 'screen_tag: WorkFlow A commute screen',
    headquarterRoute: AppRoutes.headquarterPage,
    typeRoute: AppRoutes.doubleTypePage,
    isHeadquarterContext: false,
    enableDebugTrace: true,
    traceScreenId: 'double_commute_inside',
  );

  static const CommuteModeSpec minorMode = CommuteModeSpec(
    contextKey: 'minor',
    modeKey: 'minor',
    screenTagLabel: 'screen_tag: minor commute screen',
    headquarterRoute: AppRoutes.headquarterPage,
    typeRoute: AppRoutes.minorTypePage,
    isHeadquarterContext: false,
    enableDebugTrace: true,
    traceScreenId: 'minor_commute_inside',
    saveLogPrefix: 'Minor',
  );

  static const CommuteModeSpec tripleMode = CommuteModeSpec(
    contextKey: 'triple',
    modeKey: 'triple',
    screenTagLabel: 'screen_tag: commute screen',
    headquarterRoute: AppRoutes.headquarterPage,
    typeRoute: AppRoutes.tripleTypePage,
    isHeadquarterContext: false,
    enableDebugTrace: false,
    traceScreenId: 'triple_commute_inside',
  );
}
