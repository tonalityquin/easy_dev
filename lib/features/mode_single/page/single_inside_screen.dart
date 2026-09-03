import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/command/presentation/terminal_launcher_button.dart';
import '../../../app/init/app_exit_service.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../app/init/logout_helper.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_adaptive_two_line_content.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/area_remote_settings/application/area_remote_settings_sync.dart';
import '../../../shared/secondary/application/secondary_info.dart';
import '../../../shared/secondary/application/secondary_state.dart';
import '../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../account/applications/user_state.dart';
import '../../attendance/application/common_attendance_service.dart';
import '../../dev/debug/debug_api_logger.dart';
import '../../selector/application/dev_auth.dart';
import '../controllers/single_inside_controller.dart';
import 'sheets/document/single_document_box_sheet.dart';
import 'sheets/report/single_inside_report_selector_sheet.dart';
import 'widgets/widgets/single_inside_punch_recorder_section.dart';
import 'widgets/widgets/single_inside_work_schedule_section.dart';

enum SingleInsideMode {
  leader,
  fieldUser,
}

bool _singleOperationsRoleAllowed(RoleType role) {
  return role == RoleType.dev ||
      role == RoleType.adminBillMonthlyTablet;
}

const String _tSingle = 'Single';
const String _tSingleInside = 'Single/inside';
const String _tPrefs = 'prefs';
const String _tUi = 'ui';

enum _SingleInsideMenuAction {
  developerStatus,
  logout,
  exitApp,
}

class _SingleInsideLayoutDiagnostics {
  static const int _limit = 160;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[SINGLE_BRANCH_LAYOUT][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[SINGLE_BRANCH_LAYOUT] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: 'Single 상태',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

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
    final fallback = fallbackColor ?? cs.onBackground;
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
  final controller = SingleInsideController();
  String _lastLayoutSignature = '';
  String _lastModeSignature = '';
  String _lastUserSignature = '';
  int _scheduleRevision = 0;

  @override
  void initState() {
    super.initState();
    _SingleInsideLayoutDiagnostics.log('screen_init');
    controller.initialize(context);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      await userState.ensureTodayClockInStatus();
      if (!mounted) return;
      _SingleInsideLayoutDiagnostics.log(
        'clock_state isWorking=${userState.isWorking} hasClockInToday=${userState.hasClockInToday}',
      );
      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState();
      }
    });
  }

  Future<void> _resetStaleWorkingState() async {
    try {
      _SingleInsideLayoutDiagnostics.log('stale_working_state_reset_start');
      await CommonAttendanceService.resetStaleWorkingState(
        context,
        source: 'single_inside_stale_guard',
        modeKey: 'single',
      );
      _SingleInsideLayoutDiagnostics.log('stale_working_state_reset_complete');
    } catch (e) {
      _SingleInsideLayoutDiagnostics.log('stale_working_state_reset_failure error=$e');
      await _logApiError(
        tag: 'SingleInsideScreen._resetStaleWorkingState',
        message: 'stale working state 리셋 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tPrefs],
      );
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      _SingleInsideLayoutDiagnostics.log('logout_start');
      await LogoutHelper.logoutAndGoToLogin(
        context,
        checkWorking: false,
        delay: const Duration(milliseconds: 500),
      );
    } catch (e) {
      _SingleInsideLayoutDiagnostics.log('logout_failure error=$e');
      await _logApiError(
        tag: 'SingleInsideScreen._handleLogout',
        message: '로그아웃 처리 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _handleAppExit(BuildContext context) async {
    try {
      _SingleInsideLayoutDiagnostics.log('app_exit_start');
      await AppExitService.exitApp(context);
    } catch (e) {
      _SingleInsideLayoutDiagnostics.log('app_exit_failure error=$e');
      await _logApiError(
        tag: 'SingleInsideScreen._handleAppExit',
        message: '앱 종료 처리 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _showDeveloperStatus() async {
    final media = MediaQuery.maybeOf(context);
    final userState = context.read<UserState>();
    final secondaryState = context.read<SecondaryState>();
    _SingleInsideLayoutDiagnostics.log(
      'developer_status_open viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} role=${userState.session?.role ?? ''} normalizedRole=${secondaryState.role.name} area=${userState.currentArea} division=${userState.division} operationsVisible=${_singleOperationsRoleAllowed(secondaryState.role) && secondaryState.canAccess(Section.user)} secondaryUserAccess=${secondaryState.canAccess(Section.user)}',
    );
    await _SingleInsideLayoutDiagnostics.showStatus(
      context,
      description: 'Single 화면, 운영 관리 노출 정책, 업무 Surface의 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    _SingleInsideMenuAction action,
  ) async {
    switch (action) {
      case _SingleInsideMenuAction.developerStatus:
        await _showDeveloperStatus();
        break;
      case _SingleInsideMenuAction.logout:
        await _handleLogout(context);
        break;
      case _SingleInsideMenuAction.exitApp:
        await _handleAppExit(context);
        break;
    }
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
      _SingleInsideLayoutDiagnostics.log('mode_resolved $signature');
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
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: DevAuth.devModeEnabled,
          builder: (context, developerMode, _) {
            return PopupMenuButton<_SingleInsideMenuAction>(
              tooltip: '메뉴',
              onSelected: (value) async {
                await _handleMenuAction(context, value);
              },
              itemBuilder: (context) => [
                if (developerMode)
                  const PopupMenuItem<_SingleInsideMenuAction>(
                    value: _SingleInsideMenuAction.developerStatus,
                    child: Row(
                      children: [
                        Icon(Icons.bug_report_rounded),
                        SizedBox(width: 8),
                        Text('상태 확인'),
                      ],
                    ),
                  ),
                PopupMenuItem<_SingleInsideMenuAction>(
                  value: _SingleInsideMenuAction.logout,
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: tokens.danger),
                      const SizedBox(width: 8),
                      const Text('로그아웃'),
                    ],
                  ),
                ),
                PopupMenuItem<_SingleInsideMenuAction>(
                  value: _SingleInsideMenuAction.exitApp,
                  child: Row(
                    children: [
                      Icon(
                        Icons.power_settings_new_rounded,
                        color: tokens.danger,
                      ),
                      const SizedBox(width: 8),
                      const Text('앱 종료'),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            );
          },
        ),
      ],
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
                    right: 52,
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

  Future<void> _openReport(BuildContext context) async {
    _SingleInsideLayoutDiagnostics.log('work_surface_open target=report');
    HapticFeedback.selectionClick();
    await openSingleInsideReportSelectorSheet(context);
    _SingleInsideLayoutDiagnostics.log('work_surface_closed target=report');
  }

  Future<void> _openDocuments(BuildContext context) async {
    _SingleInsideLayoutDiagnostics.log('work_surface_open target=document');
    HapticFeedback.selectionClick();
    await openSingleDocumentBox(context);
    _SingleInsideLayoutDiagnostics.log('work_surface_closed target=document');
  }

  Future<void> _openOperations(BuildContext context) async {
    final state = context.read<SecondaryState>();
    final roleAllowed = _singleOperationsRoleAllowed(state.role);
    final sectionAllowed = state.canAccess(Section.user);
    final allowed = roleAllowed && sectionAllowed;
    _SingleInsideLayoutDiagnostics.log(
      'work_surface_open target=user_management allowed=$allowed role=${state.role.name} roleAllowed=$roleAllowed sectionAllowed=$sectionAllowed reason=${state.accessDebugReason(Section.user)}',
    );
    if (!allowed) return;
    HapticFeedback.selectionClick();
    await showSecondarySideDock<void>(
      context: context,
      barrierLabel: '운영 관리',
      initialSection: Section.user,
    );
    _SingleInsideLayoutDiagnostics.log('work_surface_closed target=user_management');
  }

  void _handleScheduleChanged() {
    if (!mounted) return;
    setState(() => _scheduleRevision++);
    _SingleInsideLayoutDiagnostics.log(
      'work_schedule_changed revision=$_scheduleRevision',
    );
  }

  Widget _buildCompactBrand(double availableHeight) {
    if (availableHeight < 720) return const SizedBox.shrink();
    const height = 48.0;
    return CommonAnimatedReveal(
      offset: const Offset(0, -0.025),
      child: const SizedBox(
        height: height,
        child: _BrandTintedLogo(
          assetPath: 'assets/images/ParkinWorkin_logo.png',
          height: height,
        ),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required SingleInsideMode mode,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required bool showOperations,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 560;
        final veryCompact = constraints.maxHeight < 430;
        final horizontal = constraints.maxWidth < 420 ? 12.0 : 18.0;
        final vertical = veryCompact ? 6.0 : compact ? 8.0 : 12.0;
        final gap = veryCompact ? 4.0 : compact ? 6.0 : 10.0;
        final signature =
            'fixed_layout viewport=${constraints.maxWidth.toStringAsFixed(1)}x${constraints.maxHeight.toStringAsFixed(1)} compact=$compact veryCompact=$veryCompact horizontal=$horizontal vertical=$vertical showOperations=$showOperations mode=${mode.name} scheduleRevision=$_scheduleRevision';
        if (_lastLayoutSignature != signature) {
          _lastLayoutSignature = signature;
          _SingleInsideLayoutDiagnostics.log(signature);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, vertical, horizontal, vertical),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCompactBrand(constraints.maxHeight),
              if (constraints.maxHeight >= 720) SizedBox(height: gap),
              SingleInsideWorkScheduleSection(
                onChanged: _handleScheduleChanged,
              ),
              SizedBox(height: gap),
              SingleInsidePunchRecorderSection(
                userId: userId,
                userName: userName,
                area: area,
                division: division,
                scheduleRevision: _scheduleRevision,
              ),
              SizedBox(height: gap),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: CommonAnimatedReveal(
                    delay: const Duration(milliseconds: 90),
                    offset: const Offset(0, 0.035),
                    child: _SingleInsideWorkListSurface(
                      showReport: mode == SingleInsideMode.leader,
                      showOperations: showOperations,
                      compact: compact,
                      veryCompact: veryCompact,
                      onReport: () => _openReport(context),
                      onDocuments: () => _openDocuments(context),
                      onOperations: () => _openOperations(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: tokens.canvas,
              appBar: _buildAppBar(context),
              bottomNavigationBar: const _SingleInsideDataDownloadDock(),
              body: Consumer2<UserState, SecondaryState>(
                builder: (context, userState, secondaryState, _) {
                  final mode = _resolveMode(userState);
                  final session = userState.session;
                  if (session == null) {
                    return Center(
                      child: CircularProgressIndicator(color: tokens.accent),
                    );
                  }

                  final userId = session.id;
                  final userName = session.displayName;
                  final area = userState.currentArea;
                  final division = userState.division;
                  final roleAllowed =
                      _singleOperationsRoleAllowed(secondaryState.role);
                  final sectionAllowed =
                      secondaryState.canAccess(Section.user);
                  final showOperations = roleAllowed && sectionAllowed;

                  final userSignature =
                      'userId=$userId userName=$userName area=$area division=$division normalizedRole=${secondaryState.role.name} operationsVisible=$showOperations roleAllowed=$roleAllowed secondaryUserAccess=$sectionAllowed';
                  if (_lastUserSignature != userSignature) {
                    _lastUserSignature = userSignature;
                    _SingleInsideLayoutDiagnostics.log(
                      'punch_props $userSignature',
                    );
                  }

                  return _buildContent(
                    context: context,
                    mode: mode,
                    userId: userId,
                    userName: userName,
                    area: area,
                    division: division,
                    showOperations: showOperations,
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

class _SingleInsideWorkListSurface extends StatelessWidget {
  const _SingleInsideWorkListSurface({
    required this.showReport,
    required this.showOperations,
    required this.compact,
    required this.veryCompact,
    required this.onReport,
    required this.onDocuments,
    required this.onOperations,
  });

  final bool showReport;
  final bool showOperations;
  final bool compact;
  final bool veryCompact;
  final VoidCallback onReport;
  final VoidCallback onDocuments;
  final VoidCallback onOperations;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final rows = <Widget>[
      if (showReport)
        _SingleInsideWorkRow(
          icon: Icons.assignment_outlined,
          label: '업무 보고',
          enabled: true,
          compact: compact,
          veryCompact: veryCompact,
          onTap: onReport,
        ),
      _SingleInsideWorkRow(
        icon: Icons.folder_open_rounded,
        label: '서류함 열기',
        enabled: true,
        compact: compact,
        veryCompact: veryCompact,
        onTap: onDocuments,
      ),
      if (showOperations)
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 60),
          offset: const Offset(0, 0.025),
          child: _SingleInsideWorkRow(
            icon: Icons.admin_panel_settings_outlined,
            label: '운영 관리',
            enabled: true,
            compact: compact,
            veryCompact: veryCompact,
            onTap: onOperations,
          ),
        ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: OpsDockListSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0)
                Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
              rows[index],
            ],
          ],
        ),
      ),
    );
  }
}

class _SingleInsideWorkRow extends StatefulWidget {
  const _SingleInsideWorkRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.compact,
    required this.veryCompact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool compact;
  final bool veryCompact;
  final VoidCallback onTap;

  @override
  State<_SingleInsideWorkRow> createState() => _SingleInsideWorkRowState();
}

class _SingleInsideWorkRowState extends State<_SingleInsideWorkRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground =
        widget.enabled ? tokens.textPrimary : tokens.textDisabled;
    final iconColor = widget.enabled ? tokens.accent : tokens.iconDisabled;
    final verticalPadding = widget.veryCompact
        ? 3.0
        : widget.compact
            ? 8.0
            : 11.0;
    final iconBox = widget.veryCompact
        ? 30.0
        : widget.compact
            ? 34.0
            : 38.0;
    final iconSize = widget.veryCompact
        ? 18.0
        : widget.compact
            ? 19.0
            : 21.0;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onHighlightChanged: widget.enabled
                ? (value) {
                    if (!mounted || _pressed == value) return;
                    setState(() => _pressed = value);
                  }
                : null,
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: verticalPadding,
              ),
              color: _pressed
                  ? tokens.surfaceSelected.withOpacity(.6)
                  : Colors.transparent,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    curve: CommonUiMotion.standard,
                    width: iconBox,
                    height: iconBox,
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? tokens.accentContainer
                          : tokens.surfaceDisabled,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.icon,
                      color: iconColor,
                      size: iconSize,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: Icon(
                      widget.enabled
                          ? Icons.chevron_right_rounded
                          : Icons.lock_outline_rounded,
                      key: ValueKey<bool>(widget.enabled),
                      color: widget.enabled
                          ? tokens.iconSecondary
                          : tokens.iconDisabled,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SingleInsideDataDownloadState {
  idle,
  loading,
  success,
  failure,
}

class _SingleInsideDataDownloadDock extends StatefulWidget {
  const _SingleInsideDataDownloadDock();

  @override
  State<_SingleInsideDataDownloadDock> createState() =>
      _SingleInsideDataDownloadDockState();
}

class _SingleInsideDataDownloadDockState
    extends State<_SingleInsideDataDownloadDock> {
  _SingleInsideDataDownloadState _state = _SingleInsideDataDownloadState.idle;
  Timer? _feedbackTimer;
  String _lastLayoutSignature = '';

  bool get _busy => _state == _SingleInsideDataDownloadState.loading;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _setStateSafe(_SingleInsideDataDownloadState value) {
    if (!mounted) return;
    if (_state != value) {
      _SingleInsideLayoutDiagnostics.log(
        'download_dock_state previous=${_state.name} next=${value.name}',
      );
    }
    setState(() => _state = value);
  }

  void _scheduleIdle() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 1600), () {
      _setStateSafe(_SingleInsideDataDownloadState.idle);
    });
  }

  Future<void> _download() async {
    if (_busy) return;

    _feedbackTimer?.cancel();
    _setStateSafe(_SingleInsideDataDownloadState.loading);
    HapticFeedback.selectionClick();

    DeveloperOperationTrace? trace;
    try {
      final userState = context.read<UserState>();
      final division = userState.division.trim();
      final area = userState.currentArea.trim();

      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '다운로드 데이터 확인',
        initialMessage: '현재 지역의 SQLite Snapshot 연결 데이터를 확인하고 있습니다.',
        useCommonUi: true,
        developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
      );

      trace.log(
        'singleModePolicy=sqlite_snapshot_read_only firebaseRead=false sharedPreferencesRead=false',
        progress: 0.04,
      );
      trace.log(
        '현재 로그인 범위를 확인했습니다: divisionPresent=${division.isNotEmpty}, areaPresent=${area.isNotEmpty}',
        progress: 0.07,
      );

      final result = await AreaRemoteSettingsSync.sync(
        division: division,
        area: area,
        onLog: trace.log,
        progressStart: 0.1,
        progressEnd: 0.94,
      );

      trace.log(
        'SQLite Snapshot 연결 데이터 확인 결과: availableCount=${result.availableCount} emailAvailable=${result.emailAvailable} inviteAvailable=${result.inviteAvailable} communicationAvailable=${result.communicationAvailable}',
        progress: 0.97,
      );
      await trace.succeed('현재 지역의 SQLite Snapshot 확인이 완료되었습니다.');

      if (!mounted) return;
      _setStateSafe(_SingleInsideDataDownloadState.success);
      HapticFeedback.lightImpact();

      if (!trace.developerMode) {
        await StatusDialog.showSuccess(
          context,
          title: '다운로드 데이터 확인 완료',
          description:
              '현재 지역(${result.area})의 본사 다운로드 SQLite Snapshot을 확인했습니다.\nFirebase와 SharedPreferences는 조회하거나 갱신하지 않았습니다.\n${result.summary}',
          useCommonUi: true,
        );
      }

      _scheduleIdle();
    } catch (error, stackTrace) {
      debugPrint('[SingleInsideDataDownload] failure: $error');
      final activeTrace = trace;
      if (activeTrace != null) {
        await activeTrace.fail(
          '현재 지역의 SQLite Snapshot 확인에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (!mounted) return;
      _setStateSafe(_SingleInsideDataDownloadState.failure);
      HapticFeedback.mediumImpact();

      if (activeTrace == null || !activeTrace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: '다운로드 데이터 확인 실패',
          description:
              '현재 지역의 본사 다운로드 SQLite Snapshot을 확인하지 못했습니다.',
          useCommonUi: true,
        );
      }

      _scheduleIdle();
    }
  }

  Color _background(ColorScheme cs) {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return cs.secondaryContainer;
      case _SingleInsideDataDownloadState.loading:
        return cs.primaryContainer;
      case _SingleInsideDataDownloadState.success:
        return cs.tertiaryContainer;
      case _SingleInsideDataDownloadState.failure:
        return cs.errorContainer;
    }
  }

  Color _foreground(ColorScheme cs) {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return cs.onSecondaryContainer;
      case _SingleInsideDataDownloadState.loading:
        return cs.onPrimaryContainer;
      case _SingleInsideDataDownloadState.success:
        return cs.onTertiaryContainer;
      case _SingleInsideDataDownloadState.failure:
        return cs.onErrorContainer;
    }
  }

  String get _title {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return '다운로드 데이터 확인';
      case _SingleInsideDataDownloadState.loading:
        return 'SQLite Snapshot 확인 중';
      case _SingleInsideDataDownloadState.success:
        return '다운로드 데이터 확인 완료';
      case _SingleInsideDataDownloadState.failure:
        return '다시 확인';
    }
  }

  String get _subtitle {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return '본사 내려받기 SQLite Snapshot만 사용';
      case _SingleInsideDataDownloadState.loading:
        return '현재 지역의 저장된 연결 정보를 확인합니다';
      case _SingleInsideDataDownloadState.success:
        return 'Firebase · SharedPreferences 접근 없음';
      case _SingleInsideDataDownloadState.failure:
        return '본사 내려받기 후 다시 확인할 수 있습니다';
    }
  }

  Widget _leadingIcon({
    required Color foreground,
    required bool reduceMotion,
  }) {
    if (_state == _SingleInsideDataDownloadState.loading && !reduceMotion) {
      return SizedBox(
        key: const ValueKey<String>('loading'),
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: foreground,
        ),
      );
    }

    final icon = switch (_state) {
      _SingleInsideDataDownloadState.idle => Icons.cloud_download_rounded,
      _SingleInsideDataDownloadState.loading => Icons.sync_rounded,
      _SingleInsideDataDownloadState.success => Icons.cloud_done_rounded,
      _SingleInsideDataDownloadState.failure => Icons.refresh_rounded,
    };

    return Icon(
      icon,
      key: ValueKey<_SingleInsideDataDownloadState>(_state),
      size: 22,
      color: foreground,
    );
  }

  Future<void> _showLayoutDeveloperStatus() async {
    final media = MediaQuery.maybeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    _SingleInsideLayoutDiagnostics.log(
      'status_dialog state=${_state.name} viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} textScale=${textScale.toStringAsFixed(2)} minHeight=64.0',
    );
    await _SingleInsideLayoutDiagnostics.showStatus(
      context,
      description:
          'Single 지사 다운로드 Dock의 반응형 높이, TextScaler, 현재 상태 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    final background = _background(cs);
    final foreground = _foreground(cs);
    final media = MediaQuery.maybeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final layoutSignature =
        'state=${_state.name} viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} textScale=${textScale.toStringAsFixed(2)} minHeight=64.0 paddingY=8.0';
    if (_lastLayoutSignature != layoutSignature) {
      _lastLayoutSignature = layoutSignature;
      _SingleInsideLayoutDiagnostics.log(layoutSignature);
    }

    final dock = SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AnimatedSize(
          duration: motion,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: motion,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 64),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: foreground.withOpacity(0.14),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _busy ? null : _download,
                onLongPress: _showLayoutDeveloperStatus,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: foreground.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: motion,
                          switchInCurve: Curves.linear,
                          switchOutCurve: Curves.linear,
                          transitionBuilder: (child, animation) {
                            final fadeAnimation = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            final scaleAnimation = Tween<double>(
                              begin: 0.86,
                              end: 1,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                                reverseCurve: Curves.easeInCubic,
                              ),
                            );
                            return FadeTransition(
                              opacity: fadeAnimation,
                              child: ScaleTransition(
                                scale: scaleAnimation,
                                child: child,
                              ),
                            );
                          },
                          child: _leadingIcon(
                            foreground: foreground,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: motion,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.08),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: CommonAdaptiveTwoLineContent(
                            key: ValueKey<_SingleInsideDataDownloadState>(
                              _state,
                            ),
                            gap: 2,
                            title: Text(
                              _title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: foreground.withOpacity(0.78),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _state == _SingleInsideDataDownloadState.failure
                            ? -0.08
                            : 0,
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          _state == _SingleInsideDataDownloadState.success
                              ? Icons.check_rounded
                              : Icons.chevron_right_rounded,
                          color: foreground.withOpacity(_busy ? 0.45 : 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) {
      return Semantics(
        button: true,
        enabled: !_busy,
        label: '다운로드 데이터 확인',
        child: dock,
      );
    }

    return Semantics(
      button: true,
      enabled: !_busy,
      label: '다운로드 데이터 확인',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: dock,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - value)),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

