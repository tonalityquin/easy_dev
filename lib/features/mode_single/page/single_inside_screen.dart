import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/command/presentation/terminal_launcher_button.dart';
import '../../../app/init/app_exit_service.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../app/init/logout_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/area_remote_settings/application/local_area_capability_refresh.dart';
import '../../../shared/secondary/application/secondary_info.dart';
import '../../../shared/secondary/application/secondary_state.dart';
import '../../../shared/document/work_start_report/dashboard_start_report_form_page.dart';
import '../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../attendance/application/common_attendance_service.dart';
import '../../dev/debug/debug_api_logger.dart';
import '../application/single_inside_diagnostics.dart';
import '../application/single_operational_data_sync_workflow.dart';
import '../application/single_inside_document_action_runner.dart';
import '../controllers/single_inside_controller.dart';
import 'sheets/report/widgets/single_inside_end_report_form_page.dart';
import 'side_docks/single_inside_side_dock.dart';
import 'widgets/single_inside_bottom_action_surface.dart';
import 'widgets/single_inside_spatial_dot_map.dart';

enum SingleInsideMode {
  leader,
  fieldUser,
}

bool _singleOperationsRoleAllowed(RoleType role) {
  return role == RoleType.dev || role == RoleType.adminBillMonthlyTablet;
}

const String _tSingle = 'Single';
const String _tSingleInside = 'Single/inside';
const String _tPrefs = 'prefs';
const String _tUi = 'ui';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
}) {
  if (_contrastRatio(preferred, background) >= 3.0) return preferred;
  return fallback;
}

Future<void> _logApiError({
  required String tag,
  required String message,
  required Object error,
  Map<String, dynamic>? extra,
  List<String>? tags,
}) async {
  try {
    await DebugApiLogger().log(
      <String, dynamic>{
        'tag': tag,
        'message': message,
        'error': error.toString(),
        if (extra != null) 'extra': extra,
      },
      level: 'error',
      tags: tags,
    );
  } catch (_) {}
}

class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    this.preferredColor,
    this.fallbackColor,
  });

  final String assetPath;
  final double height;
  final Color? preferredColor;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final preferred = preferredColor ?? cs.primary;
    final fallback = fallbackColor ?? cs.onSurface;
    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferred,
      fallback: fallback,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
    );
  }
}

class SingleInsideScreen extends StatefulWidget {
  const SingleInsideScreen({
    super.key,
    this.mode,
  });

  final SingleInsideMode? mode;

  @override
  State<SingleInsideScreen> createState() => _SingleInsideScreenState();
}

class _SingleInsideScreenState extends State<SingleInsideScreen> {
  final SingleInsideController controller = SingleInsideController();
  String _lastModeSignature = '';
  String _lastUserSignature = '';
  int _scheduleRevision = 0;
  int _spatialRefreshRevision = 0;
  int _ruleRefreshRevision = 0;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    SingleInsideDiagnostics.log('screen', 'init');
    controller.initialize(context);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      await userState.ensureTodayClockInStatus();
      if (!mounted) return;
      SingleInsideDiagnostics.log(
        'attendance',
        'clock_state isWorking=${userState.isWorking} hasClockInToday=${userState.hasClockInToday}',
      );
      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState();
      }
    });
  }

  Future<void> _resetStaleWorkingState() async {
    try {
      SingleInsideDiagnostics.log('attendance', 'stale_reset_start');
      await CommonAttendanceService.resetStaleWorkingState(
        context,
        source: 'single_inside_stale_guard',
        modeKey: 'single',
      );
      SingleInsideDiagnostics.log('attendance', 'stale_reset_complete');
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'attendance',
        'stale_reset_failure error=$error stack=$stackTrace',
      );
      await _logApiError(
        tag: 'SingleInsideScreen._resetStaleWorkingState',
        message: 'stale working state 리셋 실패',
        error: error,
        tags: const <String>[_tSingle, _tSingleInside, _tPrefs],
      );
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      SingleInsideDiagnostics.log('account', 'logout_start');
      await LogoutHelper.logoutAndGoToLogin(
        context,
        checkWorking: false,
        delay: const Duration(milliseconds: 500),
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'account',
        'logout_failure error=$error stack=$stackTrace',
      );
      await _logApiError(
        tag: 'SingleInsideScreen._handleLogout',
        message: '로그아웃 처리 실패',
        error: error,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _handleAppExit(BuildContext context) async {
    try {
      SingleInsideDiagnostics.log('system', 'app_exit_start');
      await AppExitService.exitApp(context);
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'system',
        'app_exit_failure error=$error stack=$stackTrace',
      );
      await _logApiError(
        tag: 'SingleInsideScreen._handleAppExit',
        message: '앱 종료 처리 실패',
        error: error,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _showDeveloperStatus() async {
    final media = MediaQuery.maybeOf(context);
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final secondaryState = context.read<SecondaryState>();
    final operationsVisible =
        _singleOperationsRoleAllowed(secondaryState.role) &&
            secondaryState.canAccess(Section.user);
    SingleInsideDiagnostics.log(
      'status',
      'snapshot viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} role=${userState.session?.role ?? ''} normalizedRole=${secondaryState.role.name} area=${userState.currentArea} division=${userState.division} areaStateCapabilities=${LocalAreaCapabilityRefresh.keys(areaState.capabilitiesOfCurrentArea)} locationAccess=${secondaryState.canAccess(Section.location)} locationAccessReason=${secondaryState.accessDebugReason(Section.location)} operationsVisible=$operationsVisible scheduleRevision=$_scheduleRevision spatialRevision=$_spatialRefreshRevision ruleRevision=$_ruleRefreshRevision menuOpen=$_menuOpen',
    );
    await SingleInsideDiagnostics.showStatus(
      context,
      description: 'Single UI 및 SQLite 공간 상태 로그',
    );
  }

  SingleInsideMode _resolveMode(UserState userState) {
    if (widget.mode != null) return widget.mode!;
    final role = userState.session?.role.trim() ?? '';
    final mode = role == 'fieldCommon'
        ? SingleInsideMode.fieldUser
        : SingleInsideMode.leader;
    final signature = 'role=$role mode=${mode.name}';
    if (_lastModeSignature != signature) {
      _lastModeSignature = signature;
      SingleInsideDiagnostics.log('screen', 'mode_resolved $signature');
    }
    return mode;
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return AppBar(
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      leadingWidth: 48,
      leading: const SizedBox.shrink(),
      title: const TerminalLauncherButton(source: 'single_branch'),
      centerTitle: true,
      backgroundColor: tokens.surface,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      surfaceTintColor: tokens.transparent,
      shadowColor: tokens.transparent,
      toolbarHeight: kToolbarHeight,
      shape: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      flexibleSpace: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Semantics(
                    label: 'Single',
                    child: ExcludeSemantics(
                      child: CommonAnimatedReveal(
                        offset: const Offset(-0.035, 0),
                        child: _BrandTintedLogo(
                          assetPath: 'assets/images/pelican_text.png',
                          height: 54,
                          preferredColor: tokens.accent,
                          fallbackColor: tokens.textPrimary,
                        ),
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
                    top: 4,
                    bottom: 4,
                  ),
                  child: SizedBox(
                    height: kToolbarHeight - 8,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 116,
                          maxHeight: kToolbarHeight - 8,
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: DbConnectionStatusAppBarSection(
                            liveLabel: 'live DB',
                            storageLabel: '스토리지 DB',
                            spacing: 4,
                          ),
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
    );
  }

  Future<void> _openMenu() async {
    if (_menuOpen || !mounted) return;
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final secondaryState = context.read<SecondaryState>();
    final session = userState.session;
    if (session == null) return;
    final mode = _resolveMode(userState);
    final roleAllowed = _singleOperationsRoleAllowed(secondaryState.role);
    final sectionAllowed = secondaryState.canAccess(Section.user);
    final showOperations = roleAllowed && sectionAllowed;
    final areaStateDivision = areaState.currentDivision.trim();
    final currentDivision = areaStateDivision.isNotEmpty
        ? areaStateDivision
        : userState.division.trim();

    setState(() => _menuOpen = true);
    SingleInsideDiagnostics.log(
      'menu',
      'open_request mode=${mode.name} showOperations=$showOperations',
    );

    SingleInsideDockRequest? request;
    try {
      request = await showSingleInsideSideDock(
        context: context,
        userId: session.id,
        userName: session.displayName,
        area: userState.currentArea,
        division: currentDivision,
        scheduleRevision: _scheduleRevision,
        onScheduleChanged: _handleScheduleChanged,
        onDeveloperStatus: _showDeveloperStatus,
        showReport: mode == SingleInsideMode.leader,
        showOperations: showOperations,
      );
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }

    if (!mounted || request == null) return;
    await _handleDockRequest(request);
  }

  Future<void> _handleDockRequest(SingleInsideDockRequest request) async {
    SingleInsideDiagnostics.log('menu', 'handle_request request=${request.name}');
    switch (request) {
      case SingleInsideDockRequest.workStartReport:
        await _openWorkStartReport(context);
        break;
      case SingleInsideDockRequest.workEndReport:
        await _openWorkEndReport(context);
        break;
      case SingleInsideDockRequest.commuteSubmit:
        await _runDocumentAction(
          context,
          SingleInsideDocumentAction.commuteSubmit,
        );
        break;
      case SingleInsideDockRequest.restTimeSubmit:
        await _runDocumentAction(
          context,
          SingleInsideDocumentAction.restTimeSubmit,
        );
        break;
      case SingleInsideDockRequest.statementForm:
        await _runDocumentAction(
          context,
          SingleInsideDocumentAction.statementForm,
        );
        break;
      case SingleInsideDockRequest.leaveApplication:
        await _runDocumentAction(
          context,
          SingleInsideDocumentAction.leaveApplication,
        );
        break;
      case SingleInsideDockRequest.operations:
        await _openOperations(context);
        break;
      case SingleInsideDockRequest.operationalSync:
        await _runSingleOperationalSync();
        break;
      case SingleInsideDockRequest.logout:
        await _handleLogout(context);
        break;
      case SingleInsideDockRequest.exitApp:
        await _handleAppExit(context);
        break;
    }
  }

  Future<void> _openWorkStartReport(BuildContext context) async {
    SingleInsideDiagnostics.log(
      'work',
      'open target=work_start_report implementation=dashboard_shared',
    );
    await showDashboardStartReportSideDock(context: context);
    SingleInsideDiagnostics.log(
      'work',
      'closed target=work_start_report implementation=dashboard_shared',
    );
  }

  Future<void> _openWorkEndReport(BuildContext context) async {
    SingleInsideDiagnostics.log(
      'work',
      'open target=work_end_report implementation=single',
    );
    await showSingleInsideEndReportSideDock(context: context);
    SingleInsideDiagnostics.log(
      'work',
      'closed target=work_end_report implementation=single',
    );
  }

  Future<void> _runDocumentAction(
    BuildContext context,
    SingleInsideDocumentAction action,
  ) async {
    await SingleInsideDocumentActionRunner.run(context, action);
  }

  Future<void> _openOperations(BuildContext context) async {
    final state = context.read<SecondaryState>();
    final roleAllowed = _singleOperationsRoleAllowed(state.role);
    final sectionAllowed = state.canAccess(Section.user);
    final allowed = roleAllowed && sectionAllowed;
    SingleInsideDiagnostics.log(
      'work',
      'open target=user_management allowed=$allowed role=${state.role.name} roleAllowed=$roleAllowed sectionAllowed=$sectionAllowed reason=${state.accessDebugReason(Section.user)}',
    );
    if (!allowed) return;
    await showSecondarySideDock<void>(
      context: context,
      barrierLabel: '운영 관리',
      initialSection: Section.user,
    );
    SingleInsideDiagnostics.log('work', 'closed target=user_management');
  }

  Future<void> _runSingleOperationalSync() async {
    SingleInsideDiagnostics.log(
      'data',
      'operational_sync_start implementation=single_independent',
    );
    final result = await SingleOperationalDataSyncWorkflow.runCurrentArea(
      context: context,
      useCommonUi: true,
    );
    SingleInsideDiagnostics.log(
      'data',
      'operational_sync_result implementation=single_independent result=${result.name}',
    );
    if (result == SingleOperationalDataSyncResult.completed && mounted) {
      setState(() {
        _spatialRefreshRevision++;
        _ruleRefreshRevision++;
      });
    }
  }

  void _handleScheduleChanged() {
    if (!mounted) return;
    setState(() => _scheduleRevision++);
    SingleInsideDiagnostics.log(
      'schedule',
      'changed revision=$_scheduleRevision',
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: tokens.canvas,
              appBar: _buildAppBar(context),
              body: Consumer3<UserState, SecondaryState, AreaState>(
                builder: (context, userState, secondaryState, areaState, _) {
                  final mode = _resolveMode(userState);
                  final session = userState.session;
                  if (session == null) {
                    return Center(
                      child: CircularProgressIndicator(color: tokens.accent),
                    );
                  }

                  final roleAllowed =
                      _singleOperationsRoleAllowed(secondaryState.role);
                  final sectionAllowed =
                      secondaryState.canAccess(Section.user);
                  final showOperations = roleAllowed && sectionAllowed;
                  final areaStateDivision = areaState.currentDivision.trim();
                  final currentDivision = areaStateDivision.isNotEmpty
                      ? areaStateDivision
                      : userState.division.trim();
                  final userSignature =
                      'userId=${session.id} userName=${session.displayName} area=${userState.currentArea} division=$currentDivision mode=${mode.name} normalizedRole=${secondaryState.role.name} operationsVisible=$showOperations roleAllowed=$roleAllowed secondaryUserAccess=$sectionAllowed';
                  if (_lastUserSignature != userSignature) {
                    _lastUserSignature = userSignature;
                    SingleInsideDiagnostics.log('screen', userSignature);
                  }

                  final content = Column(
                    children: [
                      Expanded(
                        child: SingleInsideSpatialDotMap(
                          area: userState.currentArea,
                          refreshRevision: _spatialRefreshRevision,
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: SingleInsideBottomActionSurface(
                          division: currentDivision,
                          area: userState.currentArea,
                          refreshRevision: _ruleRefreshRevision,
                          onMenuPressed: _openMenu,
                        ),
                      ),
                    ],
                  );

                  if (reduceMotion) return content;
                  return TweenAnimationBuilder<double>(
                    key: ValueKey<String>(
                      'single_spatial_${session.id}_${userState.currentArea}',
                    ),
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: content,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
