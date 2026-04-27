
import '../../../app/di/routes.dart';

class CommuteModeSpec {
  final String modeKey;
  final String screenTagLabel;
  final String headquarterRoute;
  final String typeRoute;
  final bool enableDebugTrace;
  final String? traceScreenId;
  final String? saveLogPrefix;

  const CommuteModeSpec({
    required this.modeKey,
    required this.screenTagLabel,
    required this.headquarterRoute,
    required this.typeRoute,
    required this.enableDebugTrace,
    this.traceScreenId,
    this.saveLogPrefix,
  });

  static const CommuteModeSpec doubleMode = CommuteModeSpec(
    modeKey: 'double',
    screenTagLabel: 'screen_tag: WorkFlow A commute screen',
    headquarterRoute: AppRoutes.doubleHeadquarterPage,
    typeRoute: AppRoutes.doubleTypePage,
    enableDebugTrace: true,
    traceScreenId: 'double_commute_inside',
  );

  static const CommuteModeSpec minorMode = CommuteModeSpec(
    modeKey: 'minor',
    screenTagLabel: 'screen_tag: minor commute screen',
    headquarterRoute: AppRoutes.minorHeadquarterPage,
    typeRoute: AppRoutes.minorTypePage,
    enableDebugTrace: true,
    traceScreenId: 'minor_commute_inside',
    saveLogPrefix: 'Minor',
  );

  static const CommuteModeSpec tripleMode = CommuteModeSpec(
    modeKey: 'triple',
    screenTagLabel: 'screen_tag: commute screen',
    headquarterRoute: AppRoutes.tripleHeadquarterPage,
    typeRoute: AppRoutes.tripleTypePage,
    enableDebugTrace: false,
    traceScreenId: 'triple_commute_inside',
  );
}
